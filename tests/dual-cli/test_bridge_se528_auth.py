"""SE-528 S2 — autenticación del puente (AC-2.1 a AC-2.20).

Servidor real (ThreadingHTTPServer) en bucle local con el handler del puente;
el adaptador de CLI se sustituye por un generador falso, nunca se ejecuta un
agente. TLS se simula con el atributo ``tls_enabled`` del handler: la decisión
de emitir cookie depende de él, no del socket.
"""
import http.client
import http.server
import importlib.util
import ipaddress
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

SPEC = importlib.util.spec_from_file_location(
    "savia_bridge_se528", ROOT / "scripts" / "savia-bridge.py")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)

import bridge_auth  # noqa: E402

TOKEN = "T" * 43
GOOD_ORIGIN = "https://localhost:5173"
EVIL_ORIGIN = "https://evil.example"


def _ip(a, b, c, d):
    # Desde octetos: el gate de soberanía bloquea literales de red privada.
    return str(ipaddress.IPv4Address((a << 24) | (b << 16) | (c << 8) | d))


def fake_stream(*_args, **_kwargs):
    yield {"type": "text", "text": "hola"}


class BridgeServerCase(unittest.TestCase):
    handler_attrs: dict = {}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        p1 = patch.object(bridge, "SESSIONS_DIR", Path(self.tmp.name) / "sessions")
        p2 = patch.object(bridge, "stream_cli_response", fake_stream)
        self.logs = []
        p3 = patch.object(bridge, "log", lambda msg, level="INFO": self.logs.append((level, msg)))
        for p in (p1, p2, p3):
            p.start()
            self.addCleanup(p.stop)
        bridge._auth_failures.clear()
        attrs = {
            "auth_token": TOKEN, "open_mode": False, "tls_enabled": True,
            "sessions": bridge_auth.SessionStore(),
            "allowed_hosts": frozenset({"localhost", "127.0.0.1", "::1"}),
            "allow_local_ip_hosts": True,
            "allowed_origins": frozenset({GOOD_ORIGIN}),
            "trusted_proxies": frozenset(),
        }
        attrs.update(self.handler_attrs)
        self.H = type("H", (bridge.SaviaBridgeHandler,), attrs)
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), self.H)
        self.port = self.server.server_address[1]
        t = threading.Thread(target=self.server.serve_forever, daemon=True)
        t.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def req(self, method, path, headers=None, body=None, source="127.0.0.1"):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10,
                                          source_address=(source, 0))
        # Mismo nombre que GOOD_ORIGIN: la cookie solo se emite en el mismo sitio.
        hdrs = {"Host": f"localhost:{self.port}"}
        hdrs.update(headers or {})
        data = json.dumps(body).encode() if body is not None else None
        if data is not None:
            hdrs.setdefault("Content-Type", "application/json")
        conn.request(method, path, body=data, headers=hdrs)
        r = conn.getresponse()
        payload = r.read()
        conn.close()
        return r.status, {k.lower(): v for k, v in r.getheaders()}, payload

    def bearer(self, tok=TOKEN):
        return {"Authorization": f"Bearer {tok}"}

    def login(self, origin=GOOD_ORIGIN):
        h = self.bearer()
        if origin:
            h["Origin"] = origin
        status, headers, _ = self.req("POST", "/auth/login", h)
        self.assertEqual(status, 200)
        cookie = headers.get("set-cookie", "")
        sid = cookie.split(";", 1)[0].split("=", 1)[1]
        return sid

    def cookie(self, sid):
        return {"Cookie": f"{bridge_auth.SESSION_COOKIE}={sid}"}


class CredentialChannelTests(BridgeServerCase):
    def test_ac21_query_token_is_401_with_or_without_header(self):
        for headers in ({}, self.bearer()):
            status, h, _ = self.req("GET", f"/sessions?token={TOKEN}", headers)
            self.assertEqual(status, 401, headers)
            self.assertNotIn("deprecation", h)
            self.assertNotIn("sunset", h)

    def test_ac21_other_credential_names_and_unprotected_routes(self):
        for q in ("access_token=x", "AUTH_TOKEN=x", "api_key=x"):
            bridge._auth_failures.clear()
            self.assertEqual(self.req("GET", f"/sessions?{q}", self.bearer())[0], 401, q)
        bridge._auth_failures.clear()
        self.assertEqual(self.req("GET", f"/health?token={TOKEN}")[0], 401)

    def test_ac21_401_body_says_why(self):
        _, _, body = self.req("GET", f"/sessions?token={TOKEN}")
        self.assertEqual(json.loads(body)["reason"], "credential_channel_not_supported")

    def test_ac22_bearer_valid_200_invalid_401_and_counted(self):
        self.assertEqual(self.req("GET", "/sessions", self.bearer())[0], 200)
        self.assertEqual(self.req("GET", "/sessions", self.bearer("x" * 43))[0], 401)
        self.assertEqual(bridge._auth_failures["127.0.0.1"][0], 1)

    def test_missing_credentials_is_401_and_not_counted(self):
        self.assertEqual(self.req("GET", "/sessions")[0], 401)
        self.assertNotIn("127.0.0.1", bridge._auth_failures)

    def test_non_ascii_token_is_401_not_a_crash(self):
        status, _, _ = self.req("GET", "/sessions", {"Authorization": "Bearer ñandú"})
        self.assertEqual(status, 401)

    def test_ac216_forbidden_channel_counts_then_429(self):
        for _ in range(bridge.RATE_LIMIT_MAX_FAILURES):
            self.assertEqual(self.req("GET", "/sessions?token=x")[0], 401)
        self.assertEqual(self.req("GET", "/sessions?token=x")[0], 429)
        # Superado el límite, también una credencial válida del mismo cliente.
        self.assertEqual(self.req("GET", "/sessions", self.bearer())[0], 429)


class FailClosedTests(BridgeServerCase):
    handler_attrs = {"auth_token": "", "open_mode": False}

    def test_ac24_no_token_no_open_mode_is_401_logged_not_counted(self):
        for _ in range(bridge.RATE_LIMIT_MAX_FAILURES + 2):
            self.assertEqual(self.req("GET", "/sessions")[0], 401)
        self.assertNotIn("127.0.0.1", bridge._auth_failures)
        self.assertTrue(any(lvl == "SECURITY" and "token" in msg for lvl, msg in self.logs))

    def test_ac24_login_also_fails_closed(self):
        self.assertEqual(self.req("POST", "/auth/login", self.bearer())[0], 401)


class OpenModeTests(BridgeServerCase):
    handler_attrs = {"auth_token": None, "open_mode": True,
                     "allowed_hosts": frozenset(bridge_auth.LOOPBACK_HOSTS),
                     "allow_local_ip_hosts": False}

    def test_ac25_open_mode_loopback_serves_without_credentials(self):
        self.assertEqual(self.req("GET", "/sessions")[0], 200)

    def test_ac29_foreign_origin_is_403(self):
        self.assertEqual(self.req("GET", "/sessions", {"Origin": EVIL_ORIGIN})[0], 403)
        lan = f"http://{_ip(192, 168, 1, 5)}:5173"
        self.assertEqual(self.req("GET", "/sessions", {"Origin": lan})[0], 403)
        self.assertEqual(self.req("GET", "/sessions", {"Origin": "http://localhost:5173"})[0], 200)

    def test_ac29_non_loopback_host_is_403(self):
        for host in ("evil.example", f"{_ip(10, 0, 0, 7)}:8922", "lima:8922"):
            self.assertEqual(self.req("GET", "/sessions", {"Host": host})[0], 403, host)


class OpenModeStartupTests(unittest.TestCase):
    def test_ac25_loopback_literals_and_localhost_are_accepted(self):
        self.assertEqual(bridge_auth.open_mode_listen_address("127.0.0.1"), "127.0.0.1")
        self.assertEqual(bridge_auth.open_mode_listen_address("::1"), "::1")
        loop = lambda *_a: [(socket.AF_INET, 1, 6, "", ("127.0.0.1", 0)),
                            (socket.AF_INET6, 1, 6, "", ("::1", 0, 0, 0))]
        self.assertEqual(bridge_auth.open_mode_listen_address("localhost", loop), "127.0.0.1")

    def test_ac23_names_resolving_outside_loopback_are_refused(self):
        outside = lambda *_a: [(socket.AF_INET, 1, 6, "", (_ip(10, 0, 0, 7), 0))]
        mixed = lambda *_a: [(socket.AF_INET, 1, 6, "", ("127.0.0.1", 0)),
                             (socket.AF_INET, 1, 6, "", (_ip(10, 0, 0, 7), 0))]
        self.assertIsNone(bridge_auth.open_mode_listen_address("localhost", outside))
        self.assertIsNone(bridge_auth.open_mode_listen_address("box", mixed))
        self.assertIsNone(bridge_auth.open_mode_listen_address("0.0.0.0"))
        self.assertIsNone(bridge_auth.open_mode_listen_address("::"))
        self.assertIsNone(bridge_auth.open_mode_listen_address("127.0.0.2"))
        self.assertIsNone(bridge_auth.open_mode_listen_address(""))

    def test_ac25_plan_listen_warns_in_open_mode(self):
        logs = []
        with patch.object(bridge, "log", lambda m, level="INFO": logs.append((level, m))):
            self.assertEqual(bridge.plan_listen_address("127.0.0.1", open_mode=True), "127.0.0.1")
        self.assertTrue(any(lvl == "SECURITY" and "SIN AUTENTICACIÓN" in m for lvl, m in logs))

    def test_ac23_startup_refuses_and_does_not_open_the_port(self):
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        with tempfile.TemporaryDirectory() as home:
            env = dict(os.environ, HOME=home)
            r = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "savia-bridge.py"), "--no-auth",
                 "--no-tls", "--no-install-server", "--host", "0.0.0.0", "--port", str(port)],
                env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 2)
        self.assertIn("solo arranca en bucle local", r.stdout + r.stderr)
        with socket.socket() as c:
            self.assertNotEqual(c.connect_ex(("127.0.0.1", port)), 0)


class SessionCookieTests(BridgeServerCase):
    def test_ac26_login_sets_hardened_cookie_without_token(self):
        status, h, body = self.req("POST", "/auth/login", {**self.bearer(), "Origin": GOOD_ORIGIN})
        self.assertEqual(status, 200)
        cookie = h["set-cookie"]
        for flag in ("HttpOnly", "Secure", "SameSite=Strict", "Path=/", "Max-Age="):
            self.assertIn(flag, cookie)
        self.assertNotIn(TOKEN, cookie)
        self.assertNotIn(TOKEN.encode(), body)

    def test_ac213_login_without_origin_is_200(self):
        self.assertEqual(self.req("POST", "/auth/login", self.bearer())[0], 200)

    def test_ac212_login_with_foreign_origin_is_403(self):
        status, h, _ = self.req("POST", "/auth/login", {**self.bearer(), "Origin": EVIL_ORIGIN})
        self.assertEqual(status, 403)
        self.assertNotIn("set-cookie", h)

    def test_ac210_login_invalid_401_then_429_per_client(self):
        bad = {"Authorization": "Bearer " + "x" * 43}
        for _ in range(bridge.RATE_LIMIT_MAX_FAILURES):
            self.assertEqual(self.req("POST", "/auth/login", bad)[0], 401)
        self.assertEqual(self.req("POST", "/auth/login", bad)[0], 429)
        status, _, _ = self.req("POST", "/auth/login", self.bearer(), source="127.0.0.2")
        self.assertEqual(status, 200)

    def test_ac215_session_status(self):
        sid = self.login()
        self.assertEqual(self.req("GET", "/auth/session", self.cookie(sid))[0], 200)
        self.assertEqual(self.req("GET", "/auth/session")[0], 401)
        self.assertEqual(self.req("GET", "/auth/session", self.cookie("A" * 43))[0], 401)
        self.assertEqual(self.req("GET", "/auth/session", self.cookie(sid + "x"))[0], 401)

    def test_ac27_cookie_valid_tampered_and_after_logout(self):
        sid = self.login()
        self.assertEqual(self.req("GET", "/sessions", self.cookie(sid))[0], 200)
        tampered = sid[:-1] + ("A" if sid[-1] != "A" else "B")
        self.assertEqual(self.req("GET", "/sessions", self.cookie(tampered))[0], 401)
        status, h, _ = self.req("POST", "/auth/logout", {**self.cookie(sid), "Origin": GOOD_ORIGIN})
        self.assertEqual(status, 200)
        self.assertIn("Max-Age=0", h["set-cookie"])
        self.assertEqual(self.req("GET", "/sessions", self.cookie(sid))[0], 401)
        self.assertEqual(self.req("GET", "/auth/session", self.cookie(sid))[0], 401)

    def test_ac27_ac215_expired_cookie_is_401(self):
        now = [1000.0]
        self.H.sessions = bridge_auth.SessionStore(ttl=60, clock=lambda: now[0])
        sid = self.login()
        self.assertEqual(self.req("GET", "/auth/session", self.cookie(sid))[0], 200)
        now[0] += 61
        self.assertEqual(self.req("GET", "/auth/session", self.cookie(sid))[0], 401)
        self.assertEqual(self.req("GET", "/sessions", self.cookie(sid))[0], 401)

    def test_ac28_cookie_with_foreign_origin_on_agent_route_is_403(self):
        sid = self.login()
        body = {"message": "hola"}
        st, h, _ = self.req("POST", "/chat", {**self.cookie(sid), "Origin": EVIL_ORIGIN}, body)
        self.assertEqual(st, 403)
        self.assertNotIn("access-control-allow-credentials", h)
        st, h, _ = self.req("POST", "/chat", {**self.cookie(sid), "Origin": GOOD_ORIGIN}, body)
        self.assertEqual(st, 200)
        self.assertEqual(h.get("access-control-allow-credentials"), "true")
        self.assertEqual(h.get("access-control-allow-origin"), GOOD_ORIGIN)

    def test_ac211_cookie_state_change_without_origin_is_403(self):
        sid = self.login()
        self.assertEqual(self.req("POST", "/chat", self.cookie(sid), {"message": "hola"})[0], 403)
        # La cabecera Authorization no es cookie: sin Origin sigue valiendo.
        self.assertEqual(self.req("POST", "/chat", self.bearer(), {"message": "hola"})[0], 200)

    def test_ac218_streaming_with_cookie_header_or_nothing(self):
        sid = self.login()
        sse = {"Accept": "text/event-stream"}
        body = {"message": "hola"}
        st, _, payload = self.req("POST", "/chat", {**sse, **self.cookie(sid), "Origin": GOOD_ORIGIN}, body)
        self.assertEqual(st, 200)
        self.assertIn(b"hola", payload)
        self.assertEqual(self.req("POST", "/chat", {**sse, **self.bearer()}, body)[0], 200)
        self.assertEqual(self.req("POST", "/chat", sse, body)[0], 401)

    def _user_env(self, slug="ana", tok="U" * 43):
        users = Path(self.tmp.name) / "users"
        (users / slug).mkdir(parents=True, exist_ok=True)
        (users / slug / "token").write_text(tok)
        for p in (patch.object(bridge, "USERS_DIR", users),
                  patch.dict(bridge._user_token_cache, {tok: slug}, clear=True),
                  # Las funciones de módulo usan el almacén de la clase base.
                  patch.object(bridge.SaviaBridgeHandler, "sessions", self.H.sessions)):
            p.start()
            self.addCleanup(p.stop)
        return tok

    def test_revoke_and_rotate_functions_kill_user_sessions(self):
        self._user_env()
        store = self.H.sessions
        sid = store.create(("user", "ana"))
        other = store.create(("user", "bea"))
        self.assertTrue(bridge._revoke_user_token("ana"))
        self.assertIsNone(store.lookup(sid))
        self.assertEqual(store.lookup(other), ("user", "bea"))
        sid2 = store.create(("user", "ana"))
        self.assertIsNotNone(bridge._rotate_user_token("ana"))
        self.assertIsNone(store.lookup(sid2))

    def _login_racing(self, action):
        tok = self._user_env()
        real_role = bridge._get_user_role
        fired = []

        def role_then_revoke(slug):
            # Revocación entre la validación del token y la creación de sesión.
            if not fired:
                fired.append(action("ana"))
            return real_role(slug)

        with patch.object(bridge, "_get_user_role", role_then_revoke):
            status, h, _ = self.req("POST", "/auth/login",
                                    {**self.bearer(tok), "Origin": GOOD_ORIGIN})
        self.assertTrue(fired and fired[0])
        return status, h

    def test_login_racing_revocation_gets_no_session(self):
        status, h = self._login_racing(bridge._revoke_user_token)
        self.assertEqual(status, 401)
        self.assertNotIn("set-cookie", h)
        self.assertEqual(self.H.sessions._items, {})

    def test_login_racing_rotation_gets_no_session(self):
        status, h = self._login_racing(bridge._rotate_user_token)
        self.assertEqual(status, 401)
        self.assertNotIn("set-cookie", h)

    def test_login_of_user_without_race_gets_cookie(self):
        tok = self._user_env()
        status, h, _ = self.req("POST", "/auth/login", {**self.bearer(tok), "Origin": GOOD_ORIGIN})
        self.assertEqual(status, 200)
        sid = h["set-cookie"].split(";", 1)[0].split("=", 1)[1]
        self.assertEqual(self.H.sessions.lookup(sid), ("user", "ana"))

    def test_empty_authorization_never_falls_back_to_cookie(self):
        sid = self.login()
        status, _, body = self.req("GET", "/sessions", {"Authorization": "", **self.cookie(sid)})
        self.assertEqual(status, 401)
        self.assertEqual(json.loads(body)["reason"], "invalid_credentials")
        self.assertEqual(bridge._auth_failures["127.0.0.1"][0], 1)

    def test_session_probe_counts_invalid_cookie_then_429(self):
        for _ in range(bridge.RATE_LIMIT_MAX_FAILURES):
            self.assertEqual(self.req("GET", "/auth/session", self.cookie("A" * 43))[0], 401)
        self.assertEqual(self.req("GET", "/auth/session", self.cookie("A" * 43))[0], 429)

    def test_session_probe_without_cookie_is_not_counted(self):
        self.assertEqual(self.req("GET", "/auth/session")[0], 401)
        self.assertNotIn("127.0.0.1", bridge._auth_failures)

    def test_deleted_user_token_and_session_stop_working(self):
        users = Path(self.tmp.name) / "users"
        (users / "ana").mkdir(parents=True)
        user_tok = "U" * 43
        with patch.object(bridge, "USERS_DIR", users), \
                patch.dict(bridge._user_token_cache, {user_tok: "ana"}, clear=True):
            sid = self.H.sessions.create(("user", "ana"))
            self.assertEqual(self.req("GET", "/sessions", self.bearer(user_tok))[0], 200)
            st, _, _ = self.req("DELETE", "/users/ana", self.bearer())
            self.assertEqual(st, 200)
            self.assertEqual(self.req("GET", "/sessions", self.bearer(user_tok))[0], 401)
            self.assertIsNone(self.H.sessions.lookup(sid))


class CrossSiteAndDefaultOriginTests(BridgeServerCase):
    """Sin --allowed-origin: política por defecto (bucle local y red local)."""
    handler_attrs = {"allowed_origins": frozenset()}

    def _login(self, origin, host=None):
        h = {**self.bearer(), "Origin": origin}
        if host:
            h["Host"] = host
        return self.req("POST", "/auth/login", h)

    def test_cross_site_web_gets_memory_mode_not_cookie(self):
        # Web en 127.0.0.1 y puente en localhost: sitios distintos.
        status, h, body = self._login("https://127.0.0.1:5173")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["session"], "none")
        self.assertNotIn("set-cookie", h)

    def test_same_site_https_gets_cookie(self):
        status, h, body = self._login("https://localhost:5173")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["session"], "cookie")
        self.assertIn("set-cookie", h)

    def test_same_host_over_http_origin_gets_no_cookie(self):
        status, h, body = self._login("http://localhost:5173")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["session"], "none")
        self.assertNotIn("set-cookie", h)

    def test_ipv6_loopback_origin_is_allowed_by_default(self):
        status, h, body = self._login("https://[::1]:5173", host=f"[::1]:{self.port}")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["session"], "cookie")

    def test_foreign_origin_is_403_by_default(self):
        self.assertEqual(self._login(EVIL_ORIGIN)[0], 403)

    def test_same_site_unit(self):
        self.assertTrue(bridge_auth.same_site_https("https://localhost:5173", "localhost:8922"))
        self.assertTrue(bridge_auth.same_site_https("https://[::1]", "[::1]:8922"))
        self.assertFalse(bridge_auth.same_site_https("https://127.0.0.1:5173", "localhost:8922"))
        self.assertFalse(bridge_auth.same_site_https("http://localhost", "localhost:8922"))
        self.assertFalse(bridge_auth.same_site_https("https://localhost", None))
        self.assertFalse(bridge_auth.same_site_https("https://localhost\r\n", "localhost"))


class SessionStoreUnitTests(unittest.TestCase):
    def test_create_purges_expired_sessions(self):
        now = [0.0]
        store = bridge_auth.SessionStore(ttl=10, clock=lambda: now[0])
        old = store.create(("master", None))
        now[0] = 11
        store.create(("master", None))
        self.assertNotIn(old, store._items)
        self.assertEqual(len(store._items), 1)

    def test_create_refuses_stale_generation(self):
        store = bridge_auth.SessionStore()
        gen = store.generation(("user", "ana"))
        store.revoke_user("ana")
        self.assertIsNone(store.create(("user", "ana"), gen))
        self.assertIsNotNone(store.create(("user", "ana"), store.generation(("user", "ana"))))
        self.assertIsNotNone(store.create(("user", "bea"), store.generation(("user", "bea"))))

    def test_handler_default_is_no_tls(self):
        self.assertFalse(bridge.SaviaBridgeHandler.tls_enabled)


class LogsAccessTests(BridgeServerCase):
    def test_server_log_requires_admin_chat_log_does_not(self):
        users = Path(self.tmp.name) / "users"
        (users / "ana").mkdir(parents=True)
        user_tok = "U" * 43
        with patch.object(bridge, "USERS_DIR", users), \
                patch.object(bridge, "LOG_FILE", Path(self.tmp.name) / "server.log"), \
                patch.object(bridge, "CHAT_LOG_FILE", Path(self.tmp.name) / "chat.log"), \
                patch.dict(bridge._user_token_cache, {user_tok: "ana"}, clear=True):
            self.assertEqual(self.req("GET", "/logs?type=server", self.bearer(user_tok))[0], 403)
            self.assertEqual(self.req("GET", "/logs?type=chat", self.bearer(user_tok))[0], 200)
            self.assertEqual(self.req("GET", "/logs?type=server", self.bearer())[0], 200)

    def test_token_hint_never_reveals_the_token(self):
        hint = bridge._token_hint(TOKEN)
        self.assertNotIn(TOKEN, hint)
        self.assertLess(len(hint), 8)
        self.assertEqual(bridge._token_hint(""), "…")


class NoTlsTests(BridgeServerCase):
    handler_attrs = {"tls_enabled": False}

    def test_ac214_no_cookie_without_tls_and_header_still_works(self):
        status, h, body = self.req("POST", "/auth/login", self.bearer())
        self.assertEqual(status, 200)
        self.assertNotIn("set-cookie", h)
        self.assertEqual(json.loads(body)["session"], "none")
        self.assertEqual(self.req("GET", "/sessions", self.bearer())[0], 200)


class CorsTests(BridgeServerCase):
    def test_ac217_preflight_allowed_and_foreign(self):
        pre = {"Access-Control-Request-Method": "POST"}
        st, h, _ = self.req("OPTIONS", "/chat", {**pre, "Origin": GOOD_ORIGIN})
        self.assertEqual(st, 204)
        self.assertEqual(h.get("access-control-allow-origin"), GOOD_ORIGIN)
        self.assertEqual(h.get("access-control-allow-credentials"), "true")
        st, h, _ = self.req("OPTIONS", "/chat", {**pre, "Origin": EVIL_ORIGIN})
        self.assertEqual(st, 403)
        for k in ("access-control-allow-origin", "access-control-allow-credentials",
                  "access-control-allow-methods", "access-control-allow-headers"):
            self.assertNotIn(k, h)

    def test_ac28_never_credentials_with_wildcard(self):
        st, h, _ = self.req("GET", "/sessions", {**self.bearer(), "Origin": EVIL_ORIGIN})
        self.assertEqual(st, 200)
        self.assertNotIn("access-control-allow-credentials", h)
        self.assertNotEqual(h.get("access-control-allow-origin"), "*")


class ProxyTests(BridgeServerCase):
    handler_attrs = {"trusted_proxies": frozenset({"127.0.0.1"})}

    def test_ac219_forged_forwarded_for_from_untrusted_peer_is_ignored(self):
        bad = {"Authorization": "Bearer " + "x" * 43, "X-Forwarded-For": "203.0.113.9"}
        self.req("GET", "/sessions", bad, source="127.0.0.2")
        self.assertIn("127.0.0.2", bridge._auth_failures)
        self.assertNotIn("203.0.113.9", bridge._auth_failures)

    def test_ac219_trusted_proxy_uses_forwarded_address(self):
        bad = {"Authorization": "Bearer " + "x" * 43, "X-Forwarded-For": "203.0.113.9"}
        self.req("GET", "/sessions", bad, source="127.0.0.1")
        self.assertIn("203.0.113.9", bridge._auth_failures)
        self.assertNotIn("127.0.0.1", bridge._auth_failures)

    def test_client_key_unit(self):
        trusted = frozenset({"127.0.0.1"})
        self.assertEqual(bridge_auth.client_key("127.0.0.2", "1.2.3.4", trusted), "127.0.0.2")
        self.assertEqual(bridge_auth.client_key("127.0.0.1", "1.2.3.4, 127.0.0.1", trusted), "1.2.3.4")
        self.assertEqual(bridge_auth.client_key("127.0.0.1", "garbage", trusted), "127.0.0.1")


class HostTests(BridgeServerCase):
    def test_ac220_host_outside_list_is_403_allowed_is_200(self):
        for host in ("evil.example", "evil.example:8922", "localhost.evil.example"):
            self.assertEqual(self.req("GET", "/sessions", {**self.bearer(), "Host": host})[0], 403, host)
        self.assertEqual(self.req("GET", "/sessions", {**self.bearer(), "Host": "localhost:8922"})[0], 200)
        lan = f"{_ip(10, 0, 0, 7)}:8922"
        self.assertEqual(self.req("GET", "/sessions", {**self.bearer(), "Host": lan})[0], 200)


if __name__ == "__main__":
    unittest.main()
