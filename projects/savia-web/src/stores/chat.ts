import { defineStore } from 'pinia'
import { bridgeInit } from '../utils/bridgeAuth'
import { ref, watch } from 'vue'
import { useAuthStore } from './auth'
import type { ChatMessage, PermissionInfo } from '../types/chat'

export interface SessionInfo {
  id: string
  title: string
  createdAt: number
  lastMessageAt: number
  messageCount: number
}

const SESSIONS_KEY = 'savia:chat:sessions'
const ACTIVE_KEY = 'savia:chat:active'
const DELETED_KEY = 'savia:chat:deleted'
function messagesKey(id: string) { return `savia:chat:messages:${id}` }

function loadFromStorage<T>(key: string, fallback: T): T {
  try { const v = localStorage.getItem(key); return v ? JSON.parse(v) : fallback }
  catch { return fallback }
}

function saveToStorage(key: string, val: unknown) {
  try { localStorage.setItem(key, JSON.stringify(val)) } catch {}
}

export const useChatStore = defineStore('chat', () => {
  const messages = ref<ChatMessage[]>([])
  const sessionId = ref('')
  const currentTool = ref<string | null>(null)
  const toolActivity = ref<string[]>([])
  const toolStartTime = ref(0)
  const pendingPermission = ref<PermissionInfo | null>(null)
  const sessions = ref<SessionInfo[]>(loadFromStorage(SESSIONS_KEY, []))

  function initSession(username: string) {
    // If already initialized with messages, don't reload (prevents blank on re-mount)
    if (sessionId.value && messages.value.length > 0) return

    const slug = username.replace(/^@/, '')
    const savedActive = loadFromStorage<string>(ACTIVE_KEY, '')
    if (savedActive && sessions.value.some(s => s.id === savedActive)) {
      sessionId.value = savedActive
      messages.value = loadFromStorage(messagesKey(savedActive), [])
    } else {
      sessionId.value = `${slug}-default`
      ensureSessionEntry()
    }
  }

  function ensureSessionEntry() {
    if (!sessionId.value) return
    const exists = sessions.value.find(s => s.id === sessionId.value)
    if (!exists) {
      const date = new Date().toLocaleDateString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
      sessions.value.unshift({
        id: sessionId.value, title: `New chat — ${date}`,
        createdAt: Date.now(), lastMessageAt: Date.now(), messageCount: 0,
      })
      saveSessions()
    }
  }

  function addMessage(msg: ChatMessage) {
    messages.value.push(msg)
    const session = sessions.value.find(s => s.id === sessionId.value)
    if (session) {
      session.lastMessageAt = Date.now()
      session.messageCount = messages.value.length
      if (msg.role === 'user' && (session.title.startsWith('New chat') || session.title === 'Session')) {
        const date = new Date().toLocaleDateString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
        const digest = msg.content.slice(0, 30).replace(/\s+/g, ' ').trim()
        session.title = `${date} — ${digest}${msg.content.length > 30 ? '...' : ''}`
      }
      saveSessions()
    }
    saveMessages()
  }

  function updateLastAssistant(text: string) {
    for (let i = messages.value.length - 1; i >= 0; i--) {
      if (messages.value[i].role === 'assistant' && messages.value[i].isStreaming) {
        messages.value[i].content += text
        return
      }
    }
  }

  function addToolActivity(tool: string, detail?: string) {
    const labels: Record<string, string> = {
      Read: '📄 Reading', Bash: '⚙️ Running command', Grep: '🔍 Searching',
      Glob: '📂 Finding files', Task: '🤖 Delegating to agent',
      Write: '✏️ Writing', Edit: '✏️ Editing', WebFetch: '🌐 Fetching',
      WebSearch: '🌐 Searching web',
    }
    const label = labels[tool] || `🔧 ${tool}`
    const entry = detail ? `${label}: ${detail}` : label
    toolActivity.value.push(entry)
    if (toolActivity.value.length > 20) toolActivity.value.shift()
    currentTool.value = tool
    if (!toolStartTime.value) toolStartTime.value = Date.now()
  }

  function clearToolActivity() {
    toolActivity.value = []
    currentTool.value = null
    toolStartTime.value = 0
  }

  function finishStreaming() {
    clearToolActivity()
    for (const msg of messages.value) {
      if (msg.isStreaming) msg.isStreaming = false
    }
    currentTool.value = null
    saveMessages()
  }

  function newSession() {
    // Save current messages first
    saveMessages()
    const auth = useAuthStore()
    const slug = auth.username.replace(/^@/, '')
    const id = `${slug}-${Date.now()}`
    sessionId.value = id
    messages.value = []
    ensureSessionEntry()
    saveToStorage(ACTIVE_KEY, id)
  }

  function switchSession(id: string) {
    saveMessages()
    sessionId.value = id
    messages.value = loadFromStorage(messagesKey(id), [])
    saveToStorage(ACTIVE_KEY, id)
  }

  function deleteSession(id: string) {
    if (id === sessionId.value) return // Can't delete active
    const idx = sessions.value.findIndex(s => s.id === id)
    if (idx >= 0) {
      sessions.value.splice(idx, 1)
      saveSessions()
      // Track deleted IDs so loadSessions doesn't re-add from remote
      const deleted = loadFromStorage<string[]>(DELETED_KEY, [])
      deleted.push(id)
      saveToStorage(DELETED_KEY, deleted)
      try { localStorage.removeItem(messagesKey(id)) } catch {}
    }
  }

  function saveSessions() { saveToStorage(SESSIONS_KEY, sessions.value) }
  function saveMessages() { saveToStorage(messagesKey(sessionId.value), messages.value) }

  async function loadSessions() {
    const auth = useAuthStore()
    if (!auth.serverUrl || !auth.isLoggedIn) return
    try {
      const res = await fetch(`${auth.serverUrl}/sessions`, bridgeInit(auth.token))
      if (res.ok) {
        const data = await res.json()
        const remote = Array.isArray(data) ? data : (data.sessions ?? [])
        // Merge remote sessions with local (skip deleted ones)
        const deleted = new Set(loadFromStorage<string[]>(DELETED_KEY, []))
        for (const rs of remote) {
          if (!deleted.has(rs.id) && !sessions.value.some(s => s.id === rs.id)) {
            sessions.value.push({
              id: rs.id, title: rs.title || 'Session',
              createdAt: rs.updatedAt || Date.now(),
              lastMessageAt: rs.updatedAt || Date.now(),
              messageCount: 0,
            })
          }
        }
        saveSessions()
      }
    } catch { /* optional */ }
  }

  // Persist active session on change
  watch(sessionId, (id) => { if (id) saveToStorage(ACTIVE_KEY, id) })

  return {
    messages, sessionId, currentTool, toolActivity, toolStartTime, pendingPermission, sessions,
    initSession, addMessage, updateLastAssistant, finishStreaming, addToolActivity, clearToolActivity,
    newSession, switchSession, deleteSession, loadSessions,
  }
})
