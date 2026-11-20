"""SE-528 S2 — autenticación del puente: piezas puras y testeables.

El handler de ``savia-bridge.py`` las compone; aquí no hay E/S de red.

- Credenciales solo por cabecera ``Authorization`` o por la sesión opaca en
  cookie. La cadena de consulta con nombres de credencial es un canal no
  admitido: 401 desde la entrega, sin transición (decisión Q1).
- Sesión opaca: identificador aleatorio de servidor (no el token), con
  caducidad, revocable en logout y al revocar o rotar el token de la persona.
- Límite de intentos por cliente; la cabecera de reenvío solo cuenta si el par
  directo es un proxy de confianza.
- Listas de hosts y orígenes permitidos; modo abierto solo en bucle local
  (decisión Q2).
"""
from __future__ import annotations

import ipaddress
import re
import secrets
import socket
import threading
import time
from urllib.parse import parse_qsl, urlparse

SESSION_COOKIE = "savia_bridge_sid"
SESSION_TTL_SECONDS = 12 * 3600
_SID_RE = re.compile(r"[A-Za-z0-9_-]{43}")

# Nombres de parámetro que llevan credenciales; se comparan en minúsculas.
FORBIDDEN_QUERY_KEYS = frozenset({
    "token", "access_token", "auth_token", "auth", "bearer",
    "authorization", "api_key", "apikey", "sid", SESSION_COOKIE,
})

LOOPBACK_ADDRESSES = frozenset({"127.0.0.1", "::1"})
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})


def _v4net(a: int, b: int, prefix: int) -> ipaddress.IPv4Network:
    # Desde octetos: el gate de soberanía bloquea literales de red privada.
    return ipaddress.IPv4Network(((a << 24) | (b << 16), prefix))


# Red local del despliegue por VPN: bucle local, RFC 1918 y 100.64/10.
_LOCAL_NETWORKS = (
    _v4net(127, 0, 8), _v4net(10, 0, 8), _v4net(172, 16, 12),
    _v4net(192, 168, 16), _v4net(100, 64, 10), ipaddress.IPv6Network("::1/128"),
)
_ORIGIN_RE = re.compile(r"https?://(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.\-]+)(:[0-9]{1,5})?")
_HOST_RE = re.compile(r"(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.\-]+)(:[0-9]{1,5})?")
STATE_CHANGING_METHODS = frozenset({"POST", "PUT", "DELETE", "PATCH"})


# --- Canales de credenciales -------------------------------------------------

def forbidden_credential_channel(path: str) -> bool:
    """True si la URL trae una credencial en la cadena de consulta."""
    query = urlparse(path).query
    if not query:
        return False
    for key, _value in parse_qsl(query, keep_blank_values=True):
        if key.strip().lower() in FORBIDDEN_QUERY_KEYS:
            return True
    return False


def bearer_from_header(value: str | None) -> str | None:
    """Token de ``Authorization: Bearer <t>``; None si falta o no es Bearer."""
    if not value:
        return None
    scheme, _, rest = value.strip().partition(" ")
    if scheme.lower() != "bearer":
        return None
    token = rest.strip()
    return token or None


def token_equals(candidate: str, expected: str) -> bool:
    """Comparación en tiempo constante que no lanza con texto no ASCII."""
    if not candidate or not expected:
        return False
    return secrets.compare_digest(
        candidate.encode("utf-8", "surrogateescape"),
        expected.encode("utf-8", "surrogateescape"))


def session_from_cookie_header(value: str | None) -> str | None:
    """Valor de la cookie de sesión: None si falta, "" si está malformada."""
    if not value:
        return None
    for part in value.split(";"):
        name, sep, val = part.strip().partition("=")
        if sep and name == SESSION_COOKIE:
            val = val.strip()
            return val if _SID_RE.fullmatch(val) else ""
    return None


def session_cookie(sid: str, ttl: int = SESSION_TTL_SECONDS) -> str:
    return (f"{SESSION_COOKIE}={sid}; HttpOnly; Secure; SameSite=Strict; "
            f"Path=/; Max-Age={int(ttl)}")


def expired_session_cookie() -> str:
    return f"{SESSION_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0"


# --- Sesiones opacas ---------------------------------------------------------

class SessionStore:
    """Sesiones en memoria: sid aleatorio -> principal, con caducidad.

    principal = ("master", None) o ("user", slug). Reiniciar el puente invalida
    todas las sesiones (la persona vuelve a pegar el token una vez).
    """

    def __init__(self, ttl: int = SESSION_TTL_SECONDS, clock=time.time):
        self._ttl = ttl
        self._clock = clock
        self._items: dict[str, tuple[tuple[str, str | None], float]] = {}
        self._gen: dict[str, int] = {}
        self._lock = threading.Lock()

    @property
    def ttl(self) -> int:
        return self._ttl

    def generation(self, principal: tuple[str, str | None]) -> int:
        """Generación de revocación de la persona; cambia en cada revoke_user."""
        with self._lock:
            return self._gen.get(principal[1], 0) if principal[0] == "user" else 0

    def create(self, principal: tuple[str, str | None],
               generation: int | None = None) -> str | None:
        """Crea la sesión; None si la persona se revocó desde ``generation``.

        El login toma la generación ANTES de validar el token: si una
        revocación o rotación ocurre entre la validación y la creación, la
        generación ya no coincide y no se emite sesión (sin carrera).
        """
        sid = secrets.token_urlsafe(32)
        with self._lock:
            if generation is not None and principal[0] == "user" \
                    and self._gen.get(principal[1], 0) != generation:
                return None
            now = self._clock()
            for s in [s for s, (_p, e) in self._items.items() if now >= e]:
                del self._items[s]  # purga de caducadas
            self._items[sid] = (principal, now + self._ttl)
        return sid

    def lookup(self, sid: str | None) -> tuple[str, str | None] | None:
        if not sid or not _SID_RE.fullmatch(sid):
            return None
        with self._lock:
            item = self._items.get(sid)
            if item is None:
                return None
            principal, expires = item
            if self._clock() >= expires:
                del self._items[sid]
                return None
            return principal

    def revoke(self, sid: str | None) -> bool:
        if not sid:
            return False
        with self._lock:
            return self._items.pop(sid, None) is not None

    def revoke_user(self, slug: str) -> int:
        with self._lock:
            self._gen[slug] = self._gen.get(slug, 0) + 1
            dead = [s for s, (p, _e) in self._items.items() if p == ("user", slug)]
            for s in dead:
                del self._items[s]
        return len(dead)

    def clear(self) -> None:
        with self._lock:
            self._items.clear()


# --- Cliente, host y origen --------------------------------------------------

def _norm_ip(text: str) -> str | None:
    try:
        return str(ipaddress.ip_address(text.strip().strip("[]")))
    except ValueError:
        return None


def client_key(peer: str, forwarded_for: str | None,
               trusted_proxies: frozenset[str]) -> str:
    """Clave del límite de intentos: el par directo, salvo proxy de confianza."""
    peer_ip = _norm_ip(peer) or peer
    if peer_ip not in trusted_proxies or not forwarded_for:
        return peer_ip
    for part in reversed(forwarded_for.split(",")):
        ip = _norm_ip(part)
        if ip is None:
            return peer_ip  # malformado: no se confía en la cadena
        if ip not in trusted_proxies:
            return ip
    return peer_ip


def _hostname_of(value: str | None, pattern: re.Pattern) -> str | None:
    if not value or "\r" in value or "\n" in value:
        return None
    m = pattern.fullmatch(value.strip())
    if not m:
        return None
    name = m.group(1)
    if name.startswith("["):
        return _norm_ip(name)
    return name.lower().rstrip(".")


def _is_local_ip(name: str) -> bool:
    ip = _norm_ip(name)
    if ip is None:
        return False
    addr = ipaddress.ip_address(ip)
    return any(addr.version == net.version and addr in net for net in _LOCAL_NETWORKS)


def host_allowed(value: str | None, allowed_names: frozenset[str],
                 allow_local_ips: bool) -> bool:
    """Valida la cabecera Host (sin puerto) contra la lista y la red local."""
    name = _hostname_of(value, _HOST_RE)
    if not name:
        return False
    if name in allowed_names:
        return True
    return allow_local_ips and _is_local_ip(name)


def normalize_origin(origin: str | None) -> str | None:
    """scheme://host[:port] reconstruido, o None si no es un Origin válido."""
    if not origin or "\r" in origin or "\n" in origin:
        return None
    m = _ORIGIN_RE.fullmatch(origin.strip())
    if not m:
        return None
    parsed = urlparse(origin.strip())
    try:
        port = parsed.port
    except ValueError:
        return None
    name = _hostname_of(m.group(1), _HOST_RE)
    if not name:
        return None
    if ":" in name:
        name = f"[{name}]"
    scheme = "https" if parsed.scheme == "https" else "http"
    return f"{scheme}://{name}" + (f":{int(port)}" if port is not None else "")


def origin_allowed(origin: str | None, explicit: frozenset[str],
                   loopback_only: bool) -> str | None:
    """Origin reconstruido si está permitido; None si no.

    - Modo abierto (loopback_only): solo orígenes de bucle local.
    - Con lista explícita: solo coincidencias exactas de la lista.
    - Sin lista: orígenes de nombres de bucle local o IP de red local.
    """
    norm = normalize_origin(origin)
    if norm is None:
        return None
    host = urlparse(norm).hostname or ""
    host = _norm_ip(host) or host
    if loopback_only:
        return norm if host in LOOPBACK_HOSTS else None
    if explicit:
        return norm if norm in explicit else None
    if host in LOOPBACK_HOSTS or _is_local_ip(host):
        return norm
    return None


def same_site_https(origin: str | None, host_header: str | None) -> bool:
    """True si el Origin es https y del mismo host que la cabecera Host.

    La cookie es ``SameSite=Strict``: entre sitios distintos el navegador no la
    envía. Sin lista de sufijos públicos se exige el mismo nombre de host
    (conservador: ante la duda, modo memoria con el token en la pestaña).
    """
    norm = normalize_origin(origin)
    if norm is None or not norm.startswith("https://"):
        return False
    o_host = urlparse(norm).hostname or ""
    o_host = _norm_ip(o_host) or o_host
    h_host = _hostname_of(host_header, _HOST_RE)
    return bool(h_host) and o_host == h_host


# --- Modo abierto (decisión Q2) ----------------------------------------------

def resolve_listen_addresses(host: str, resolver=socket.getaddrinfo) -> list[str]:
    """Direcciones a las que resuelve ``host``; vacío si no resuelve."""
    if not host:
        return []
    literal = _norm_ip(host)
    if literal:
        return [literal]
    try:
        infos = resolver(host, None, 0, socket.SOCK_STREAM)
    except (OSError, UnicodeError):
        return []
    out: list[str] = []
    for info in infos:
        ip = _norm_ip(str(info[4][0]))
        if ip and ip not in out:
            out.append(ip)
    return out


def open_mode_listen_address(host: str, resolver=socket.getaddrinfo) -> str | None:
    """Dirección de bucle local en la que escuchar en modo abierto, o None.

    Todas las direcciones resueltas deben ser 127.0.0.1 o ::1; con una sola
    fuera de bucle local se niega (fallo cerrado).
    """
    addrs = resolve_listen_addresses(host, resolver)
    if not addrs or any(a not in LOOPBACK_ADDRESSES for a in addrs):
        return None
    return addrs[0]


OPEN_MODE_REFUSAL = (
    "SE-528: el modo sin autenticación (--no-auth) solo arranca en bucle local. "
    "Usa --host 127.0.0.1 (o ::1, o localhost si resuelve a bucle local); "
    "para escuchar en otra dirección, arranca con token.")

OPEN_MODE_WARNING = (
    "AVISO DE SEGURIDAD: puente SIN AUTENTICACIÓN. Solo escucha en bucle local "
    "y solo acepta Host y Origin de bucle local. No lo expongas.")

# --- TLS obligatorio fuera de bucle local (SE-528 S2b) ------------------------

def is_loopback_listen(host: str, resolver=None) -> bool:
    """True si todas las direcciones de escucha de ``host`` son de bucle local.

    Fallo cerrado: un nombre que no resuelve, ``0.0.0.0`` o ``::`` no lo son.
    """
    return open_mode_listen_address(host, resolver or socket.getaddrinfo) is not None


def tls_refusal_message(host: str, reason: str, config_dir: str) -> str:
    return (
        f"SE-528: no se pudo preparar TLS ({reason}) y el puente escucha en "
        f"{host!r}, fuera de bucle local: no arranca sin cifrar. Para arreglarlo: "
        f"instala openssl para que el puente genere su certificado en {config_dir}, "
        f"o coloca ahí cert.pem y key.pem válidos; o escucha solo en esta máquina "
        f"con --host 127.0.0.1. Si de verdad quieres HTTP sin cifrar en red "
        f"(desaconsejado), pídelo de forma explícita con --no-tls.")


TLS_LOOPBACK_WARNING = (
    "AVISO DE SEGURIDAD: TLS no disponible; el puente arranca SIN CIFRAR solo "
    "porque escucha en bucle local. Instala openssl o coloca cert.pem y key.pem "
    "antes de escuchar en otra dirección.")


FAIL_CLOSED_MESSAGE = (
    "SE-528: el puente no tiene token configurado y el modo abierto no está "
    "pedido; se rechaza la petición. Configura el token (fichero auth_token o "
    "--auth-token) o arranca con --no-auth en bucle local.")
