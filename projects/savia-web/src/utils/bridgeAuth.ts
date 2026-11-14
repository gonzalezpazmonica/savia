// SE-528 (lado web del S2). Credenciales solo por cabecera Authorization o por
// la sesión opaca del puente (cookie HttpOnly que esta página no puede leer).

export type SessionMode = 'cookie' | 'memory' | ''

// Mismos nombres que rechaza el puente en la cadena de consulta.
const CREDENTIAL_KEYS = new Set([
  'token', 'access_token', 'auth_token', 'auth', 'bearer',
  'authorization', 'api_key', 'apikey', 'sid', 'savia_bridge_sid',
])

export const LEGACY_LINK_REASON = 'credential_channel_not_supported'

export function authHeaders(token: string): Record<string, string> {
  return token ? { Authorization: `Bearer ${token}` } : {}
}

/** Opciones de fetch al puente: cabecera si hay token y cookie de sesión. */
export function bridgeInit(token: string, init: RequestInit = {}): RequestInit {
  return {
    ...init,
    credentials: 'include',
    headers: { ...(init.headers as Record<string, string> || {}), ...authHeaders(token) },
  }
}

export function hasLegacyCredentialInUrl(search: string): boolean {
  if (!search) return false
  for (const key of new URLSearchParams(search).keys()) {
    if (CREDENTIAL_KEYS.has(key.trim().toLowerCase())) return true
  }
  return false
}

/** Quita de la barra de direcciones las credenciales de un enlace antiguo. */
export function stripLegacyCredentialFromUrl(): boolean {
  const { pathname, search, hash } = window.location
  if (!hasLegacyCredentialInUrl(search)) return false
  const params = new URLSearchParams(search)
  for (const key of [...params.keys()]) {
    if (CREDENTIAL_KEYS.has(key.trim().toLowerCase())) params.delete(key)
  }
  const q = params.toString()
  window.history.replaceState(window.history.state, '', `${pathname}${q ? `?${q}` : ''}${hash}`)
  return true
}

/**
 * True si la página y el puente son https y del mismo host. La cookie del
 * puente es SameSite=Strict: entre sitios distintos el navegador no la envía.
 * Sin lista de sufijos públicos se exige el mismo nombre (conservador).
 */
export function sameSiteHttps(serverUrl: string, pageHref: string): boolean {
  try {
    const a = new URL(serverUrl)
    const b = new URL(pageHref)
    return a.protocol === 'https:' && b.protocol === 'https:'
      && a.hostname.toLowerCase() === b.hostname.toLowerCase()
  } catch { return false }
}

/**
 * Modo de sesión tras POST /auth/login. Cookie solo si el puente la emitió Y
 * la página es del mismo sitio; si no, el token vive en la memoria de la pestaña.
 */
export function sessionModeFromLogin(body: unknown, serverUrl: string,
                                     pageHref: string = window.location.href): SessionMode {
  const session = (body as { session?: string } | null)?.session
  return session === 'cookie' && sameSiteHttps(serverUrl, pageHref) ? 'cookie' : 'memory'
}
