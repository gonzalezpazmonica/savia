import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { TeamMember } from '../types/bridge'

import { bridgeInit, type SessionMode } from '../utils/bridgeAuth'

// SE-528: el token nunca se guarda en el navegador. Solo se conserva lo no
// secreto (dirección del puente, usuario y modo de sesión). La sesión por
// cookie la emite el puente con HttpOnly: esta página no puede leerla.
const LEGACY_COOKIE = 'savia_session'
const CONN_COOKIE = 'savia_connection'

interface ConnInfo { serverUrl?: string; username?: string; mode?: SessionMode; token?: string }

function readConnCookie(): ConnInfo | null {
  const match = document.cookie.split('; ').find(c => c.startsWith(`${CONN_COOKIE}=`))
  if (!match) return null
  try { return JSON.parse(decodeURIComponent(match.split('=').slice(1).join('='))) }
  catch { return null }
}

function readLegacyCookie(): ConnInfo | null {
  const match = document.cookie.split('; ').find(c => c.startsWith(`${LEGACY_COOKIE}=`))
  if (!match) return null
  try { return JSON.parse(decodeURIComponent(match.split('=').slice(1).join('='))) }
  catch { return null }
}

function writeConnCookie(serverUrl: string, username: string, mode: SessionMode) {
  const val = JSON.stringify({ serverUrl, username, mode })
  document.cookie = `${CONN_COOKIE}=${encodeURIComponent(val)}; path=/; max-age=31536000; SameSite=Strict`
}

/** Q3: borra la sesión antigua que guardaba el token en una cookie legible. */
function purgeLegacyToken(): ConnInfo {
  const legacy = readLegacyCookie()
  const conn = readConnCookie()
  const info: ConnInfo = {
    serverUrl: conn?.serverUrl || legacy?.serverUrl,
    username: conn?.username || legacy?.username,
    mode: conn?.token || legacy ? '' : conn?.mode || '',
  }
  if (legacy) document.cookie = `${LEGACY_COOKIE}=; path=/; max-age=0`
  if (conn?.token || legacy) writeConnCookie(info.serverUrl || '', info.username || '', '')
  return info
}

export const useAuthStore = defineStore('auth', () => {
  const saved = purgeLegacyToken()
  const serverUrl = ref(saved.serverUrl || 'https://localhost:8922')
  const username = ref(saved.username || '')
  // Solo en memoria de la pestaña (modo sin sesión por cookie).
  const token = ref('')
  const sessionMode = ref<SessionMode>(saved.mode || '')
  const connected = ref(false)
  const profile = ref<TeamMember | null>(null)
  const role = ref<'admin' | 'user'>('user')
  // Línea que explica por qué se vuelve al formulario (Q5).
  const notice = ref('')

  const profileName = computed(() => profile.value?.name || username.value || '')
  const isLoggedIn = computed(() => connected.value && !!username.value
    && (!!token.value || sessionMode.value === 'cookie'))
  const isAdmin = computed(() => role.value === 'admin')
  const hasCookie = computed(() => sessionMode.value === 'cookie')

  function login(url: string, user: string, tok: string, member: TeamMember | null,
                 mode: SessionMode = 'memory') {
    serverUrl.value = url
    username.value = user
    sessionMode.value = mode === 'cookie' ? 'cookie' : 'memory'
    // Con sesión por cookie el cliente no conserva el token tras el login.
    token.value = sessionMode.value === 'cookie' ? '' : tok
    profile.value = member
    connected.value = true
    notice.value = ''
    writeConnCookie(url, user, sessionMode.value === 'cookie' ? 'cookie' : '')
  }

  /** Tras recargar: solo la sesión por cookie sobrevive; se comprueba en el puente. */
  async function restore(): Promise<boolean> {
    if (sessionMode.value !== 'cookie' || !username.value) {
      sessionMode.value = ''
      return false
    }
    try {
      const res = await fetch(`${serverUrl.value}/auth/session`, bridgeInit(''))
      if (res.ok) { connected.value = true; return true }
    } catch { /* puente inalcanzable: formulario */ }
    sessionMode.value = ''
    connected.value = false
    writeConnCookie(serverUrl.value, username.value, '')
    return false
  }

  function setProfile(member: TeamMember) { profile.value = member }
  function setConnected(ok: boolean) { connected.value = ok }

  async function logout() {
    if (sessionMode.value === 'cookie') {
      try { await fetch(`${serverUrl.value}/auth/logout`, bridgeInit('', { method: 'POST' })) }
      catch { /* la cookie caduca sola */ }
    }
    connected.value = false
    token.value = ''
    username.value = ''
    profile.value = null
    sessionMode.value = ''
    writeConnCookie(serverUrl.value, '', '')
  }

  // Legacy compat — useBridge reads these
  const host = computed(() => { try { return new URL(serverUrl.value).hostname } catch { return 'localhost' } })
  const port = computed(() => { try { return new URL(serverUrl.value).port || '8922' } catch { return '8922' } })
  const useTls = computed(() => serverUrl.value.startsWith('https'))

  function save(h: string, p: string, t: string, tls: boolean) {
    const proto = tls ? 'https' : 'http'
    serverUrl.value = `${proto}://${h}:${p}`
    token.value = t
    writeConnCookie(serverUrl.value, username.value, sessionMode.value)
  }

  return {
    serverUrl, username, token, connected, profile, profileName, role,
    isLoggedIn, isAdmin, hasCookie, host, port, useTls, sessionMode, notice,
    login, logout, restore, setProfile, setConnected, save,
  }
})
