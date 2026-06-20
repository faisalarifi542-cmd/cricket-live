# CricPro Admin Panel - Implementation Plan

## Current Status (Inspected)

### ✅ Backend Already Implemented
- **Authentication System**: JWT + refresh tokens, rate limiting, password management
- **RBAC System**: 5 roles (Super Admin, Admin, Editor, Support, Read Only) with granular permissions
- **Audit Logging**: Complete audit trail for all admin actions
- **Admin Routes Implemented**:
  - `/admin/login`, `/admin/logout`, `/admin/refresh`, `/admin/me`
  - `/admin/streams` - Full CRUD + health checks
  - `/admin/matches` - List, view, override, refresh
  - `/admin/providers` - Full CRUD + API key management
  - `/admin/api-keys` - Public API key management
  - `/admin/app-settings` - Settings CRUD
  - `/admin/homepage/*` - Sections, featured items, banners

### ✅ Frontend Setup Complete
- Next.js 14 + TypeScript + Tailwind CSS
- Package dependencies installed
- Type definitions created (admin.ts, stream.ts)
- API client library (lib/api.ts)
- Auth helpers (lib/auth.ts)
- Utility functions (lib/utils.ts)

## 🚧 What Needs to Be Built

### Phase 1: Core UI Components (Priority: HIGH)
- [ ] Toast/notification system components
- [ ] Badge component
- [ ] Table component
- [ ] Dialog/Modal component
- [ ] Select/Dropdown component
- [ ] Tabs component
- [ ] Switch/Toggle component
- [ ] Label component
- [ ] Textarea component
- [ ] Loading skeleton component
- [ ] Empty state component
- [ ] Status badge component

### Phase 2: Layout Components (Priority: HIGH)
- [ ] AdminShell (main layout wrapper)
- [ ] AdminSidebar (navigation)
- [ ] AdminTopbar (header with user menu)
- [ ] AdminBreadcrumbs
- [ ] PageHeader component

### Phase 3: Admin Pages - Authentication (Priority: HIGH)
- [ ] `/login` - Login page
- [ ] Protected route wrapper/middleware

### Phase 4: Admin Pages - Core Features (Priority: HIGH)
- [ ] `/dashboard` - Overview with stats cards
- [ ] `/matches` - Matches manager with tabs
- [ ] `/matches/[id]` - Match detail with streams
- [ ] `/streams` - Live streams manager
- [ ] `/streams/[id]` - Stream detail/edit
- [ ] `/providers` - API providers manager
- [ ] `/api-keys` - API keys manager
- [ ] `/settings` - App settings manager
- [ ] `/homepage` - Home manager

### Phase 5: Backend Routes - Missing Endpoints (Priority: HIGH)
- [ ] `GET /admin/dashboard` - Dashboard stats
- [ ] `GET /admin/stats` - System stats
- [ ] Cache management routes
- [ ] Health & logs routes
- [ ] Admin users CRUD routes
- [ ] Roles CRUD routes
- [ ] Audit logs viewing route

### Phase 6: Admin Pages - Content Management (Priority: MEDIUM)
- [ ] `/series` - Series manager
- [ ] `/series/[id]` - Series detail
- [ ] `/teams` - Teams manager
- [ ] `/teams/[id]` - Team detail
- [ ] `/players` - Players manager
- [ ] `/players/[id]` - Player detail
- [ ] `/schedule` - Schedule manager
- [ ] `/news` - News manager
- [ ] `/news/[id]` - News detail/edit

### Phase 7: Admin Pages - Operations (Priority: MEDIUM)
- [ ] `/notifications` - Notifications manager
- [ ] `/ads` - Ads settings manager
- [ ] `/cache` - Cache manager
- [ ] `/health` - Health & logs viewer

### Phase 8: Admin Pages - User Management (Priority: MEDIUM)
- [ ] `/users` - Admin users manager
- [ ] `/users/[id]` - User detail/edit
- [ ] `/roles` - Roles & permissions manager
- [ ] `/audit-logs` - Audit logs viewer

### Phase 9: Backend Routes - Content Management (Priority: MEDIUM)
- [ ] Series management routes
- [ ] Teams management routes
- [ ] Players management routes
- [ ] Schedule management routes
- [ ] News management routes
- [ ] Notifications routes

### Phase 10: Backend Routes - Operations (Priority: MEDIUM)
- [ ] Ads management routes
- [ ] Cache management routes (flush, warm, stats)
- [ ] Health check routes
- [ ] Logs viewing routes

### Phase 11: Backend Routes - User Management (Priority: LOW)
- [ ] Admin users CRUD
- [ ] Roles CRUD
- [ ] Audit logs query endpoint

### Phase 12: Integration & Testing (Priority: HIGH)
- [ ] Install dependencies (`npm install` in admin-panel)
- [ ] Test all API endpoints
- [ ] Test authentication flow
- [ ] Test RBAC permissions
- [ ] Test audit logging
- [ ] Verify responsive design
- [ ] Test all CRUD operations

### Phase 13: Flutter Integration (Priority: MEDIUM)
- [ ] Update Flutter to use `/app-config`
- [ ] Update Flutter to use `/home-config`
- [ ] Update Flutter Live Player to use `/match/:id/streams`
- [ ] Implement maintenance mode handling
- [ ] Implement force update handling
- [ ] Implement feature toggles

## Implementation Order

1. **Immediate (Today)**:
   - Complete core UI components
   - Build layout components
   - Create login page
   - Create dashboard page
   - Implement missing backend dashboard/stats endpoint

2. **Next (Tomorrow)**:
   - Build matches manager page
   - Build streams manager page
   - Build providers manager page
   - Build API keys manager page
   - Build settings manager page

3. **Following Days**:
   - Content management pages (series, teams, players, schedule, news)
   - Operations pages (notifications, ads, cache, health)
   - User management pages (users, roles, audit logs)
   - Corresponding backend routes

4. **Final**:
   - Testing and bug fixes
   - Flutter integration
   - Documentation
   - Deployment guide

## Database Schema Status

### ✅ Tables Already Created (from migration)
- `admin_users`
- `admin_roles`
- `admin_permissions`
- `admin_user_roles`
- `admin_role_permissions`
- `admin_audit_logs`
- `match_streams`
- `stream_servers`
- `stream_sources`
- `stream_health_checks`
- `api_providers`
- `provider_api_keys`
- `app_settings`
- `homepage_sections`
- `featured_matches`
- `featured_series`
- `featured_news`
- `app_banners`
- `match_overrides`
- `cache_events`

### 🚧 Tables Needed (if not exist)
- `push_notifications`
- `notification_campaigns`
- `ad_settings`
- `ad_placements`
- `system_logs`

## Tech Stack Confirmed

### Backend
- Node.js + Fastify
- MySQL
- Redis
- PM2
- Nginx
- Deployed at: https://api.webcrichd.co

### Admin Frontend
- Next.js 14
- React 18
- TypeScript
- Tailwind CSS
- shadcn/ui components
- Axios for API calls
- Zustand for state management
- date-fns for date formatting
- Recharts for charts/graphs

### Design System
- Dark navy background (#0a0e27)
- Cyan/blue gradient accents
- Glassmorphism cards
- Rounded corners
- Smooth animations
- Premium feel

## Next Steps

Starting with Phase 1-3 to build the foundation, then systematically implementing each phase.
