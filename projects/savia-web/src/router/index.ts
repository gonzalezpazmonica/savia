import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: () => import('../pages/HomePage.vue') },
    { path: '/chat', component: () => import('../pages/ChatPage.vue') },
    { path: '/commands', component: () => import('../pages/CommandsPage.vue') },
    { path: '/backlog', component: () => import('../pages/BacklogPage.vue') },
    { path: '/kanban', redirect: '/backlog' },
    { path: '/pipelines', component: () => import('../pages/PipelinesPage.vue') },
    { path: '/integrations', component: () => import('../pages/IntegrationsPage.vue') },
    { path: '/approvals', component: () => import('../pages/ApprovalsPage.vue') },
    { path: '/timelog', component: () => import('../pages/TimeLogPage.vue') },
    { path: '/files', component: () => import('../pages/FileBrowserPage.vue') },
    { path: '/profile', component: () => import('../pages/ProfilePage.vue') },
    { path: '/settings', component: () => import('../pages/SettingsPage.vue') },
    { path: '/admin/users', component: () => import('../pages/AdminUsersPage.vue'), meta: { requiresAdmin: true } },
    {
      path: '/reports',
      component: () => import('../pages/reports/ReportsLayout.vue'),
      redirect: '/reports/sprint',
      children: [
        { path: 'sprint', component: () => import('../pages/reports/SprintReportPage.vue') },
        { path: 'board-flow', component: () => import('../pages/reports/BoardFlowPage.vue') },
        { path: 'team-workload', component: () => import('../pages/reports/TeamWorkloadPage.vue') },
        { path: 'portfolio', component: () => import('../pages/reports/PortfolioPage.vue') },
        { path: 'dora', component: () => import('../pages/reports/DoraMetricsPage.vue') },
        { path: 'quality', component: () => import('../pages/reports/QualityPage.vue') },
        { path: 'debt', component: () => import('../pages/reports/DebtPage.vue') },
      ]
    },
  ]
})

// Admin route guard — waits for role to be loaded
router.beforeEach(async (to) => {
  if (to.meta.requiresAdmin) {
    const { useAuthStore } = await import('../stores/auth')
    const auth = useAuthStore()
    // If role hasn't been loaded yet, try to fetch it
    if (auth.role === 'user' && auth.isLoggedIn) {
      try {
        const { bridgeInit } = await import('../utils/bridgeAuth')
        const res = await fetch(`${auth.serverUrl}/auth/me`, bridgeInit(auth.token))
        if (res.ok) {
          const data = await res.json()
          auth.role = data.role === 'admin' ? 'admin' : 'user'
        }
      } catch { /* keep default */ }
    }
    if (!auth.isAdmin) return '/'
  }
})

export default router
