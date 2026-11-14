<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { bridgeInit } from '../utils/bridgeAuth'
const { t } = useI18n()
import { ref, onMounted } from 'vue'
import { Shield, Plus, RefreshCw, Ban, Trash2, Copy } from 'lucide-vue-next'
import { useBridge } from '../composables/useBridge'
import { useAuthStore } from '../stores/auth'
import LoadingSpinner from '../components/LoadingSpinner.vue'

interface UserEntry { slug: string; name: string; email: string; role: string; created: string; status: string }

const { get, post } = useBridge()
const auth = useAuthStore()
const users = ref<UserEntry[]>([])
const loading = ref(false)
const showAdd = ref(false)
const newSlug = ref(''); const newName = ref(''); const newEmail = ref(''); const newRole = ref('user')
const generatedToken = ref<string | null>(null)
const error = ref('')

async function loadUsers() {
  loading.value = true
  const data = await get<{ users: UserEntry[] }>('/users')
  users.value = data?.users ?? []
  loading.value = false
}

async function createUser() {
  if (!newSlug.value.trim()) { error.value = '@handle is required'; return }
  error.value = ''
  const data = await post<{ token: string; slug: string }>('/users', {
    slug: newSlug.value.trim(), name: newName.value, email: newEmail.value, role: newRole.value,
  })
  if (data?.token) {
    generatedToken.value = data.token
    newSlug.value = ''; newName.value = ''; newEmail.value = ''
    await loadUsers()
  } else { error.value = 'Failed to create user' }
}

async function rotateToken(slug: string) {
  const data = await post<{ token: string }>(`/users/${slug}/rotate-token`, {})
  if (data?.token) generatedToken.value = data.token
}

async function revokeUser(slug: string) {
  await post(`/users/${slug}/revoke`, {})
  await loadUsers()
}

async function deleteUser(slug: string) {
  try {
    await fetch(`${auth.serverUrl}/users/${slug}`, bridgeInit(auth.token, { method: 'DELETE' }))
    await loadUsers()
  } catch {}
}

async function changeRole(slug: string, role: string) {
  try {
    await fetch(`${auth.serverUrl}/users/${slug}`, bridgeInit(auth.token, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ role }),
    }))
    await loadUsers()
  } catch {}
}

function copyToken() {
  if (generatedToken.value) navigator.clipboard.writeText(generatedToken.value)
}

onMounted(() => loadUsers())
</script>

<template>
  <div class="admin-users">
    <div class="page-header">
      <h1><Shield :size="20" /> User Management</h1>
      <button class="btn-add" @click="showAdd = !showAdd"><Plus :size="14" /> Add User</button>
    </div>

    <!-- Token display modal -->
    <div v-if="generatedToken" class="token-modal">
      <div class="token-card">
        <h3>User Token (save it now)</h3>
        <p class="token-warn">This token will NOT be shown again.</p>
        <div class="token-box">
          <code>{{ generatedToken }}</code>
          <button @click="copyToken"><Copy :size="14" /></button>
        </div>
        <button class="btn-dismiss" @click="generatedToken = null">Done</button>
      </div>
    </div>

    <!-- Add user form -->
    <div v-if="showAdd" class="add-form">
      <input v-model="newSlug" placeholder="@handle (e.g. alice)" class="input" />
      <input v-model="newName" placeholder="Full name" class="input" />
      <input v-model="newEmail" placeholder="Email" class="input" />
      <select v-model="newRole" class="input"><option value="user">user</option><option value="admin">admin</option></select>
      <button class="btn-create" @click="createUser">{{ t('common.create') }}</button>
      <p v-if="error" class="error">{{ error }}</p>
    </div>

    <LoadingSpinner v-if="loading" />
    <table v-else class="users-table">
      <thead><tr><th>Handle</th><th>Name</th><th>Role</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>
        <tr v-for="u in users" :key="u.slug">
          <td class="slug">@{{ u.slug }}</td>
          <td>{{ u.name }}</td>
          <td>
            <select :value="u.role" @change="changeRole(u.slug, ($event.target as HTMLSelectElement).value)" class="role-select">
              <option value="admin">admin</option><option value="user">user</option>
            </select>
          </td>
          <td><span :class="['status-badge', u.status]">{{ u.status }}</span></td>
          <td class="actions">
            <button @click="rotateToken(u.slug)" title="Rotate token"><RefreshCw :size="14" /></button>
            <button @click="revokeUser(u.slug)" title="Revoke"><Ban :size="14" /></button>
            <button @click="deleteUser(u.slug)" title="Delete" class="btn-danger"><Trash2 :size="14" /></button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.admin-users { max-width: 900px; }
.page-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; }
.page-header h1 { font-size: 18px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
.btn-add { display: flex; align-items: center; gap: 4px; padding: 6px 14px; background: var(--savia-primary); color: white; border: none; border-radius: var(--savia-radius); cursor: pointer; font-size: 12px; }
.add-form { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; align-items: center; }
.input { padding: 6px 10px; border: 1px solid var(--savia-outline); border-radius: var(--savia-radius); font-size: 13px; }
.btn-create { padding: 6px 14px; background: var(--savia-primary); color: white; border: none; border-radius: var(--savia-radius); cursor: pointer; }
.error { color: var(--savia-error); font-size: 12px; }
.users-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.users-table th { text-align: left; padding: 8px; border-bottom: 2px solid var(--savia-surface-variant); font-size: 12px; color: var(--savia-outline); }
.users-table td { padding: 8px; border-bottom: 1px solid var(--savia-surface-variant); }
.slug { font-family: monospace; font-weight: 500; }
.role-select { padding: 2px 6px; border: 1px solid var(--savia-outline); border-radius: var(--savia-radius); font-size: 12px; }
.status-badge { padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 500; }
.status-badge.active { background: var(--savia-success-container); color: var(--savia-success); }
.status-badge.revoked { background: var(--savia-error-container); color: var(--savia-error); }
.actions { display: flex; gap: 4px; }
.actions button { background: var(--savia-surface-variant); border: none; padding: 4px 6px; border-radius: var(--savia-radius); cursor: pointer; display: flex; color: var(--savia-on-surface); }
.actions button:hover { background: var(--savia-outline); color: white; }
.btn-danger:hover { background: var(--savia-error); color: white; }
.token-modal { position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 9999; }
.token-card { background: var(--savia-surface); padding: 24px; border-radius: var(--savia-radius-lg); max-width: 500px; }
.token-card h3 { margin-bottom: 8px; }
.token-warn { color: var(--savia-error); font-size: 13px; margin-bottom: 12px; }
.token-box { display: flex; gap: 8px; align-items: center; background: var(--savia-background); padding: 10px; border-radius: var(--savia-radius); margin-bottom: 12px; }
.token-box code { flex: 1; font-size: 12px; word-break: break-all; }
.token-box button { background: var(--savia-surface-variant); border: none; padding: 4px 8px; border-radius: var(--savia-radius); cursor: pointer; }
.btn-dismiss { padding: 8px 20px; background: var(--savia-primary); color: white; border: none; border-radius: var(--savia-radius); cursor: pointer; }
</style>
