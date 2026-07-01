# Layouts (`lib/debt_stalker_web/components/layouts/`)

This folder contains the root and live layouts for the browser UI. Layouts wrap pages and LiveViews with common chrome: navigation, flash messages, styles, and scripts.

## Responsibilities

- Provide the root HTML shell for all browser responses.
- Provide the live layout used by LiveViews.
- Include common UI chrome such as the nav bar, flash area, and footer.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `layouts.ex` | Defines the root and live layouts as Phoenix components. |
| `root.html.heex` | Root HTML template with `<head>` and `<body>` tags. |
| `app.html.heex` | Default app layout for non-live pages. |
| `live.html.heex` | Live layout used by `use DebtStalkerWeb, :live_view`. |

## Public API

### `DebtStalkerWeb.Layouts`

#### `root(assigns :: map()) :: Phoenix.LiveView.Rendered.t()`

Renders the root layout with the page title, meta tags, and asset links.

## Important notes

- Layouts are referenced from `lib/debt_stalker_web.ex` via the `:html`, `:live_view`, and `:controller` macro definitions.
- The root layout sets `put_root_layout` in the browser pipeline in `lib/debt_stalker_web/router.ex`.
- Flash messages are rendered by `<.flash />` from `DebtStalkerWeb.CoreComponents` inside the live layout.

## Where to look next

- `lib/debt_stalker_web.ex` — macro definitions that wire layouts.
- `lib/debt_stalker_web/router.ex` — browser pipeline and root layout.
- `lib/debt_stalker_web/components/core_components.ex` — flash and header components used in layouts.
