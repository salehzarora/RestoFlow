# restoflow_design_system

Shared **themeable UI foundations**. Flutter package.

Per [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) section 3 this package owns the
shared theme, design tokens, and (later) RTL/LTR-aware layout primitives
(DECISION D-014).

## Public surface
- `restoflowBaseTheme({Color seedColor, Brightness brightness})` — a seeded
  Material 3 `ThemeData` with consistent app-bar, card, button, chip, and
  divider styling. Defaults to the brand seed (light).
- `kRestoflowSeedColor` — the RestoFlow brand seed colour.
- `RestoflowSpacing` — 4-point spacing scale (`xs`…`xxl`).
- `RestoflowRadii` — corner-radius scale (`sm`, `md`, `lg`, `pill`).

## Deferred
Richer shared widgets and bidi (RTL/LTR) layout primitives land in later UI
tickets. Brand colour is data-driven by the seed; direction is handled by the
localization delegates, not the theme.
