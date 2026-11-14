<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '../stores/auth'
import type { TeamMember, TeamResponse } from '../types/bridge'
import RegisterWizard from './RegisterWizard.vue'
import { Eye, EyeOff } from 'lucide-vue-next'
import { bridgeInit, sessionModeFromLogin, type SessionMode } from '../utils/bridgeAuth'

const auth = useAuthStore()
const serverUrl = ref(auth.serverUrl || 'https://localhost:8922')
const username = ref(auth.username || '')
const token = ref(auth.token || '')
let mode: SessionMode = 'memory'
const error = ref('')
const certHint = ref(false)
const loading = ref(false)
const showRegister = ref(false)
const slug = ref('')
const showToken = ref(false)

function timedFetch(url: string, opts: RequestInit = {}, ms = 8000): Promise<Response> {
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), ms)
  return fetch(url, { ...opts, signal: ctrl.signal }).finally(() => clearTimeout(timer))
}

async function connect() {
  error.value = ''
  certHint.value = false
  if (!username.value.startsWith('@')) { error.value = 'Username must start with @'; return }
  loading.value = true
  slug.value = username.value.replace(/^@/, '')

  try {
    const healthRes = await timedFetch(`${serverUrl.value}/health`)
    if (!healthRes.ok) { error.value = 'Bridge not reachable at this URL'; loading.value = false; return }

    const teamRes = await timedFetch(`${serverUrl.value}/team`, {
      headers: { 'Authorization': `Bearer ${token.value}` },
    })
    if (!teamRes.ok) { error.value = 'Invalid token or unauthorized'; loading.value = false; return }

    const team: TeamResponse = await teamRes.json()
    const member = team.members.find((m: TeamMember) => m.slug === slug.value) || null

    // Exchange master token for per-user token
    const regRes = await timedFetch(`${serverUrl.value}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token.value}` },
      body: JSON.stringify({ username: slug.value }),
    })
    if (regRes.ok) {
      const regData = await regRes.json()
      if (regData.user_token) token.value = regData.user_token
    }

    // SE-528: el puente emite la sesión opaca (cookie HttpOnly) si hay TLS y
    // mismo sitio; la web lo comprueba también. Si no, el token vive solo en la
    // memoria de la pestaña.
    mode = 'memory'
    try {
      const loginRes = await timedFetch(`${serverUrl.value}/auth/login`,
        bridgeInit(token.value, { method: 'POST' }))
      if (loginRes.ok) mode = sessionModeFromLogin(await loginRes.json(), serverUrl.value)
    } catch { /* sin sesión por cookie: modo memoria */ }

    if (member) {
      auth.login(serverUrl.value, username.value, token.value, member, mode)
    } else {
      auth.save(new URL(serverUrl.value).hostname, new URL(serverUrl.value).port || '8922', token.value, serverUrl.value.startsWith('https'))
      auth.token = token.value
      auth.serverUrl = serverUrl.value
      showRegister.value = true
    }
  } catch (e: unknown) {
    const isTls = serverUrl.value.startsWith('https')
    const isTimeout = e instanceof DOMException && e.name === 'AbortError'
    if (isTimeout) {
      error.value = 'Connection timed out. Is the Bridge running?'
    } else {
      error.value = 'Could not connect. Check the server URL and try again.'
    }
    if (isTls) {
      certHint.value = true
    }
  }
  loading.value = false
}

function onRegistered(member: TeamMember) {
  showRegister.value = false
  auth.login(serverUrl.value, username.value, token.value, member, mode)
}
</script>

<template>
  <div class="login-overlay">
    <RegisterWizard v-if="showRegister" :slug="slug" :server-url="serverUrl"
      :token="token" @registered="onRegistered" @cancel="showRegister = false" />
    <div v-else class="login-card glass-card">
      <img src="/savia-logo.png" alt="Savia" class="login-logo" />
      <h1>Savia</h1>
      <p class="login-subtitle">Connect to your PM-Workspace</p>
      <p v-if="auth.notice" class="login-notice" data-testid="login-notice" role="status">{{ auth.notice }}</p>
      <div class="form-row">
        <label>Server URL</label>
        <input v-model="serverUrl" placeholder="https://localhost:8922" />
      </div>
      <div class="form-row">
        <label>Username</label>
        <input v-model="username" placeholder="@your-handle" />
      </div>
      <div class="form-row">
        <label>Access Token</label>
        <div class="input-with-eye">
          <input v-model="token" :type="showToken ? 'text' : 'password'" placeholder="Bearer token from ~/.savia/bridge/auth_token" />
          <button type="button" class="btn-eye" data-testid="toggle-token" @click="showToken = !showToken"
            :aria-label="showToken ? 'Hide token' : 'Show token'">
            <EyeOff v-if="showToken" :size="18" /><Eye v-else :size="18" />
          </button>
        </div>
      </div>
      <div v-if="error" class="error-msg">
        <p>{{ error }}</p>
        <div v-if="certHint" class="cert-hint" data-testid="cert-hint">
          <p>Open <a :href="`${serverUrl}/health`" target="_blank" rel="noopener">{{ serverUrl }}/health</a>
            in your browser and accept the certificate, then try again.</p>
        </div>
      </div>
      <button class="btn-connect" @click="connect" :disabled="loading">
        {{ loading ? 'Connecting...' : 'Connect' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.login-overlay { position: fixed; inset: 0; z-index: 1000; background: var(--savia-background); display: flex; align-items: center; justify-content: center; }
.login-card { padding: 40px; width: 420px; text-align: center; }
.login-logo { width: 80px; height: 80px; margin-bottom: 8px; }
h1 { font-size: 26px; color: var(--savia-primary); margin-bottom: 4px; }
.login-notice { font-size: 13px; color: var(--savia-on-surface); background: var(--savia-surface-variant, transparent); border: 1px solid var(--savia-outline); border-radius: var(--savia-radius); padding: 8px 12px; margin-bottom: 16px; text-align: left; }
.login-subtitle { font-size: 13px; color: var(--savia-on-surface-variant); margin-bottom: 24px; }
.form-row { margin-bottom: 12px; text-align: left; }
.form-row label { display: block; font-size: 12px; color: var(--savia-on-surface-variant); margin-bottom: 3px; }
.form-row input { width: 100%; padding: 10px 12px; border: 1px solid var(--savia-outline); border-radius: var(--savia-radius); font-size: 14px; background: var(--savia-background); color: var(--savia-on-surface); transition: border-color var(--savia-transition); }
.form-row input:focus { border-color: var(--savia-primary); outline: none; }
.input-with-eye { position: relative; }
.input-with-eye input { width: 100%; padding-right: 40px; box-sizing: border-box; }
.btn-eye { position: absolute; right: 0; top: 0; height: 100%; width: 40px; display: flex; align-items: center; justify-content: center; background: none; border: none; cursor: pointer; color: var(--savia-on-surface-variant); }
.btn-eye:hover { color: var(--savia-primary); }
.btn-connect { width: 100%; padding: 12px; background: var(--savia-primary); color: white; border-radius: var(--savia-radius); font-weight: 600; font-size: 15px; margin-top: 16px; transition: background var(--savia-transition), box-shadow var(--savia-transition); box-shadow: 0 2px 8px rgba(107, 76, 154, 0.3); }
.btn-connect:hover:not(:disabled) { background: var(--savia-primary-dark); }
.btn-connect:disabled { opacity: 0.6; cursor: not-allowed; }
.error-msg { color: var(--savia-error); font-size: 12px; margin: 8px 0; text-align: left; }
.cert-hint { margin-top: 6px; padding: 8px 10px; background: var(--savia-surface-variant, #f5f0fa); border-radius: var(--savia-radius); color: var(--savia-on-surface-variant); font-size: 12px; line-height: 1.4; }
.cert-hint a { color: var(--savia-primary); text-decoration: underline; word-break: break-all; }
@media (max-width: 479px) { .login-card { width: calc(100% - 32px); padding: 24px 20px; } .login-logo { width: 60px; height: 60px; } h1 { font-size: 22px; } }
</style>
