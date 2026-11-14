<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useAuthStore } from '../stores/auth'
import { useProjectStore } from '../stores/project'
import AppSidebar from '../components/AppSidebar.vue'
import AppTopBar from '../components/AppTopBar.vue'
import LoginPage from '../components/LoginPage.vue'
import type { TeamResponse } from '../types/bridge'
import { bridgeInit, stripLegacyCredentialFromUrl } from '../utils/bridgeAuth'
import i18n from '../locales'

const sidebarCollapsed = ref(false)
const auth = useAuthStore()
const projectStore = useProjectStore()

onMounted(async () => {
  // SE-528 Q5: un enlace antiguo con la credencial en la dirección lleva al
  // formulario con una línea que dice por qué; la credencial se quita del historial.
  if (stripLegacyCredentialFromUrl()) auth.notice = i18n.global.t('auth.legacyLink')
  // Tras recargar solo sobrevive la sesión por cookie; el puente la confirma.
  const hadSession = auth.hasCookie
  if (!auth.isLoggedIn && hadSession) {
    if (await auth.restore()) {
      try {
        const slug = auth.username.replace(/^@/, '')
        const res = await fetch(`${auth.serverUrl}/team`, bridgeInit(auth.token))
        if (res.ok) {
          const team: TeamResponse = await res.json()
          auth.setProfile(team.members.find(m => m.slug === slug) || { slug, name: auth.username })
        }
      } catch { /* perfil opcional */ }
    } else if (!auth.notice) {
      auth.notice = i18n.global.t('auth.sessionExpired')
    }
  }
  if (auth.isLoggedIn) {
    try {
      const res = await fetch(`${auth.serverUrl}/auth/me`, bridgeInit(auth.token))
      if (res.ok) {
        const data = await res.json()
        auth.role = data.role === 'admin' ? 'admin' : 'user'
      }
    } catch { /* default to user */ }
  }
  await projectStore.load()
})
</script>

<template>
  <LoginPage v-if="!auth.isLoggedIn" />
  <div v-else class="layout" :class="{ collapsed: sidebarCollapsed }">
    <AppSidebar :collapsed="sidebarCollapsed" />
    <div class="main">
      <AppTopBar @toggle-sidebar="sidebarCollapsed = !sidebarCollapsed" />
      <main class="content">
        <router-view />
      </main>
    </div>
  </div>
</template>

<style scoped>
.layout { display: flex; height: 100vh; overflow: hidden; }
.main { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
.content {
  flex: 1; overflow-y: auto; padding: 24px;
  background: var(--savia-background);
}
</style>
