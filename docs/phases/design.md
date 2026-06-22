# Debt Stalker — UI/UX Design Plan

> Scope: design a modern, easy-to-navigate companion interface for two personas:
> 1. **Applicant** — submits a credit application and tracks its status.
> 2. **Admin** — reviews, filters, and updates applications.
>
> After this plan is approved, the contents will be copied to `docs/phases/design.md`
> and implementation will follow the project’s TDD / rs-guard workflow.

---

## 1. Current State Snapshot

The app boots and already has working LiveViews, but it still looks like the
Phoenix default install:

- `/` renders the generic Phoenix welcome page.
- `/applications`, `/applications/new`, and `/applications/:id` exist but have
  no top-level navigation, no empty states, and no persona separation.
- The list is a plain HTML table with hand-rolled Tailwind classes.
- The create form and detail page are functional but visually bare.
- There is no browser-level authentication/role separation; the API uses JWT
  `read`/`update` roles.

The underlying backend already supports everything we need for the UI:
country-specific validation, provider enrichment, status transitions, audit
logs, PubSub broadcasts, and cursor pagination.

---

## 2. Design Goals

1. **Instantly understandable** — a first-time user knows which door is for
   applicants and which is for admins.
2. **Mobile-first responsive** — forms and tables work on small screens.
3. **Accessible** — semantic HTML, visible focus states, ARIA live regions for
   real-time updates.
4. **Secure-by-default** — PII is redacted, status controls are gated, and
   full identity documents are never shown.
5. **Consistent** — built on the existing DaisyUI + Tailwind foundation and the
   `CoreComponents` already shipped with Phoenix 1.8.
6. **Real-time** — status changes and new applications appear without a page
   refresh.

---

## 3. Personas & User Journeys

### 3.1 Applicant

> “I need to request credit. I want a simple form, confirmation that it was
> received, and a way to check what happens next.”

Journey:

1. Lands on home page and chooses **Apply for credit**.
2. Fills a guided form (country → personal info → amount/income).
3. Sees inline validation and country-specific document hints (DNI / CURP).
4. Submits and sees a confirmation screen with a reference ID and current
   status.
5. Can return to the reference URL to track progress.

### 3.2 Admin

> “I review credit applications. I need a dashboard, filters, and a quick way
> to move an application through the status pipeline.”

Journey:

1. Lands on home page and chooses **Admin review**.
2. Sees a dashboard with KPI cards and a list of applications.
3. Filters by country, status, date range.
4. Opens an application detail to see summary, provider data, audit trail, and
   allowed status transitions.
5. Updates status; the change reflects immediately across all connected admins.

---

## 4. Information Architecture

| Path | Persona | Purpose |
|------|---------|---------|
| `/` | Both | Landing page with persona split |
| `/apply` | Applicant | New application form |
| `/apply/:id/confirmation` | Applicant | Success + status tracker |
| `/admin` | Admin | Dashboard with KPIs and recent applications |
| `/admin/applications` | Admin | Full applications list with filters |
| `/admin/applications/:id` | Admin | Detail, audit log, status update |
| `/api/...` | API clients | Unchanged JWT-protected API |

Legacy LiveView routes (`/applications`, `/applications/new`,
`/applications/:id`) will be kept but redirected to the appropriate new paths
so bookmarks and tests do not break during the transition.

---

## 5. Page Designs

### 5.1 Landing Page (`/`)

A clean, centered page with:

- Project logo / wordmark (Debt Stalker).
- Short value proposition.
- Two large CTA cards side by side on desktop, stacked on mobile:
  - **Apply for credit** — primary color, icon `hero-document-text`.
  - **Admin review** — neutral/secondary color, icon `hero-shield-check`.
- Theme toggle in the corner.
- Footer with a link to the API docs / Postman collection.

Clicking **Apply for credit** sets the applicant session role and redirects.
Clicking **Admin review** goes to a password-protected login page; successful
authentication sets the admin session role.

### 5.2 Applicant Form (`/apply`)

- Step indicator: **Country → Details → Submit** (visual, not multi-page).
- Form fields:
  - Country select (ES / MX for MVP; extensible).
  - Full name.
  - Identity document input with dynamic placeholder/hint per country.
  - Requested amount and monthly income, with localised currency feel.
- Inline validation on `phx-change` using existing changeset errors.
- Submit button with loading state.
- On success: redirect to `/apply/:id/confirmation`.

### 5.3 Confirmation / Tracker (`/apply/:id/confirmation`)

- Hero card with:
  - Reference ID (copy-to-clipboard).
  - Current status badge.
  - “Additional review required” warning if applicable.
- Summary of submitted data (document redacted to last-4).
- Friendly explanation of next steps based on status.
- Real-time status updates via PubSub subscription to
  `"applications:#{id}"`.

### 5.4 Admin Dashboard (`/admin`)

- KPI cards in a responsive grid:
  - Total applications
  - Pending risk
  - Awaiting additional review
  - Approved / Rejected today
  - Provider errors
- A compact “Recent applications” table (last 10).
- Quick filter chips by country/status.
- Link to full list.

### 5.5 Admin List (`/admin/applications`)

- Filter bar:
  - Country select.
  - Status select.
  - Date-from / date-to inputs.
  - Clear filters button.
- Responsive table (DaisyUI `table`) with:
  - Country flag/icon + code.
  - Applicant name.
  - Redacted document.
  - Requested amount.
  - Status badge.
  - Review flag.
  - Application date.
  - View action.
- Cursor pagination (“Load more” / “Next page”).
- Real-time row insertion/status update with a subtle highlight animation.
- Empty state illustration when filters return nothing.

### 5.6 Admin Detail (`/admin/applications/:id`)

- Two-column layout on desktop, single column on mobile.
- Left column:
  - Summary card with all fields.
  - Status badge and review flag.
  - Collapsible provider summary JSON.
- Right column:
  - **Status update** card with select + button (only when transitions exist).
  - **Audit trail** timeline (newest first) showing actor, from/to status,
    timestamp.
- Real-time refresh of status and audit trail via PubSub.

---

## 6. Design System

We will stay inside the existing Tailwind + DaisyUI setup and extend it rather
than replace it.

### 6.1 Tokens (DaisyUI variables already present)

- `primary` for applicant actions and positive progress.
- `secondary` / `neutral` for admin chrome.
- `success`, `warning`, `error`, `info` semantic colors for status badges and
  alerts.
- `base-*` for surfaces and text.

### 6.2 Components to add/extend

| Component | Location | Purpose |
|-----------|----------|---------|
| `app` layout | `DebtStalkerWeb.Layouts` | Persistent navbar, flash group, main container |
| `navbar` | `DebtStalkerWeb.Layouts` | Logo, role-aware nav links, theme toggle |
| `status_badge` | `DebtStalkerWeb.Components.UI` | Colored badge per application status |
| `stat_card` | `DebtStalkerWeb.Components.UI` | Dashboard KPI cards |
| `empty_state` | `DebtStalkerWeb.Components.UI` | Friendly empty list/message |
| `audit_timeline` | `DebtStalkerWeb.Components.UI` | Audit log entries |
| `page_header` | reuse `CoreComponents.header/1` | Page titles with actions |

### 6.3 Status badge color map

| Status | Badge class |
|--------|-------------|
| `submitted` | `badge badge-info` |
| `pending_risk` | `badge badge-warning` |
| `additional_review` | `badge badge-secondary` |
| `approved` | `badge badge-success` |
| `rejected` | `badge badge-error` |
| `provider_error` | `badge badge-neutral` |
| `cancelled` | `badge badge-ghost` |

---

## 7. Navigation & Role Model

### 7.1 Browser session role

For the companion UI we introduce a simple session role:

- `:applicant` — can access `/apply` and `/apply/:id/confirmation`.
- `:admin` — can access `/admin`, `/admin/applications`,
  `/admin/applications/:id`.
- Unset role is redirected to `/`.

Implementation:

- `DebtStalkerWeb.Plugs.AssignRole` reads the role from the session and assigns
  `:current_role` to the connection.
- `PageController.set_role/2` sets the applicant role when the landing CTA is
  submitted; admin role is only set through `PageController.do_login/2`.
- A LiveView `on_mount` hook `DebtStalkerWeb.Live.RoleAuth` enforces the role
  per LiveView module (`:applicant`, `:admin`, or `:any`).
- The API continues to use its existing JWT `read`/`update` roles unchanged.

### 7.2 Navbar links

**Applicant view:**
- Logo → `/apply`
- Theme toggle
- “Help / About” link

**Admin view:**
- Logo → `/admin`
- Dashboard, Applications
- Theme toggle
- “Switch to applicant view” link (resets role)

---

## 8. Real-Time Behavior

Keep the existing PubSub topics and add UX polish:

- Admin list subscribes to `"applications:list"`.
  - New row: prepend/insert with a highlight animation.
  - Status change: update the status badge in place.
- Admin detail and applicant tracker subscribe to
  `"applications:#{id}"`.
  - Status change: update badge, show a toast, refresh audit trail.
- Use `Phoenix.Flash` / existing toast component for transient notifications.

---

## 9. Responsive & Accessibility

- Tables on mobile wrap into horizontal scroll or card list (DaisyUI
  `table-zebra` + `overflow-x-auto`).
- Touch targets ≥ 44 px.
- Form inputs use explicit `<label>` elements.
- Focus rings visible for keyboard navigation.
- Status badges have text alternatives; no color-only meaning.
- Real-time updates use `aria-live="polite"` so screen readers announce them
  without stealing focus.

---

## 10. PII & Security UX

- Identity documents always rendered with `CreditApplication.redact_document/1`
  (`****1234`).
- Full provider raw payloads are never shown; only the normalized
  `provider_summary` fields, displayed in a collapsible panel.
- Admin status actions respect `Applications.allowed_transitions/1`.
- Browser role separation prevents applicants from reaching the admin list.

---

## 11. Implementation Roadmap

| Phase | Work | Files to touch |
|-------|------|----------------|
| **A. Shell & navigation** | New root layout with navbar, landing page, role plug/hook, admin login, route updates | `components/layouts.ex`, `components/layouts/root.html.heex`, `page_html/home.html.heex`, `page_html/login.html.heex`, `plugs/assign_role.ex`, `live/role_auth.ex`, `page_controller.ex`, `router.ex` |
| **B. Applicant flow** | Apply form (reuse/create LiveView), confirmation/tracker, empty/success states | `live/apply/application_form_live.ex`, `live/apply/application_confirmation_live.ex`, `components/ui.ex` |
| **C. Admin flow** | Dashboard KPIs, admin list with filters, detail with audit + status update | `live/admin/dashboard_live.ex`, `live/admin/applications_live.ex`, `live/admin/application_detail_live.ex`, `components/ui.ex` |
| **D. Polish & tests** | Responsive pass, real-time highlight/toast, LiveView tests for each persona, route redirects | Tests under `test/debt_stalker_web/live/`, `router.ex` |

---

## 12. Success Criteria

1. A user can open `/`, pick **Apply for credit**, submit a valid ES/MX
   application, and see a confirmation with a live-updating status badge.
2. A user can open `/`, pick **Admin review**, see a dashboard, filter the
   list, open a detail, and update a status.
3. The admin list updates in real time when a new application is created or a
   status changes.
4. All new pages pass `mix format`, `mix credo --strict`, and the added
   LiveView tests.
5. Identity documents are redacted everywhere in the UI.
6. The design is responsive down to 375 px width.

---

## 13. Open Decisions / Notes

- **Role gating**: applicants use a lightweight session role; admins use a
  single shared password (env-configured) for the companion UI. This is not a
  full identity provider. The same hooks and plugs can be extended later without
  changing page designs.
- **Logo**: for the MVP we can use a text wordmark plus a Heroicon; a custom
  SVG logo can be added later without structural changes.
- **Language**: UI text will be in English; i18n can be layered on later using
  the existing Gettext backend.
