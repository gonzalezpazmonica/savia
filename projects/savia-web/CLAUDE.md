# Savia Web — Vue.js Client for PM-Workspace

> Web client that connects to Savia Bridge for full PM-Workspace access.

---

## Stack

```
FRAMEWORK          = "Vue 3 (Composition API, script setup)"
LANGUAGE           = "TypeScript"
BUILD_TOOL         = "Vite 6"
STATE_MANAGEMENT   = "Pinia"
ROUTING            = "Vue Router 4 (admin route guard)"
I18N               = "vue-i18n 9 (ES default, EN included)"
CHARTS             = "ECharts 5 + vue-echarts 7"
MARKDOWN           = "marked (LinkedIn-style rendering in viewer + chat)"
AUTH               = "Per-user tokens + roles (admin/user); SE-528: token solo en memoria o sesión opaca HttpOnly del puente; nunca en la URL ni en el almacenamiento del navegador"
DEV_PORT           = 5173
DEV_PROTOCOL       = "HTTPS (uses Bridge certs from ~/.savia/bridge/)"
BRIDGE_DEFAULT_URL = "https://localhost:8922"
```

## Architecture

```
src/
├── composables/    ← Bridge API (get/post), SSE streaming (cancelable), report fetching
├── stores/         ← Pinia stores (8): auth, dashboard, chat, reports, project, backlog, pipeline, integrations
├── locales/        ← i18n JSON (es.json, en.json) + index.ts plugin
├── pages/          ← 13 route-level pages
├── components/     ← 28 components: backlog/(5), files/(3), charts/(10), ChatSessionList, ProjectSelector, CreateProjectModal...
├── layouts/        ← MainLayout with sidebar + topbar + role loading
├── router/         ← Vue Router with admin guard
└── styles/         ← CSS variables (Savia palette) + global styles
```

## Key Features

- **Chat**: SSE streaming, markdown in bubbles (headings, tables, lists, code), tool activity feed (live progress while Savia works), session management (list/switch/new/delete/persist), multi-thread (session-scoped streaming), user identity injection
- **Backlog**: 3-level hierarchy (Spec>PBI>Task), tree+kanban, editing, type icons, filters (type/state/person), state persistence
- **Project Selector**: TopBar dropdown + Create Project modal. All stores reload on switch
- **User Management**: Admin panel `/admin/users`. CRUD, roles (admin/user), token rotation
- **i18n**: All pages + sidebar use `$t()`. ES+EN
- **File Browser**: Breadcrumb, markdown viewer (frontmatter card, tables), editor for .md
- **Reports**: 7 sub-pages with ECharts

## Testing

```bash
npm test              # Unit tests (vitest, 42 files, 228 tests)
npm run e2e           # E2E tests (playwright, 18 files, ~150 tests)
npm run test:coverage # Coverage report (threshold 80%)
```

## Bridge Endpoints

`/auth/login` `/auth/logout` `/auth/session` `/auth/me` `/chat` `/sessions` `/projects` `/backlog` `/files` `/files/content` `/users` `/users/{slug}` `/users/{slug}/rotate-token` `/dashboard` `/reports/*`
