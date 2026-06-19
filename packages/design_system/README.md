# restoflow_design_system

Shared **themeable UI foundations** (a.k.a. the `design` package in the
checklist's older wording). Flutter package.

Per [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) section 3 this package will own
themed widgets and RTL/LTR-aware layout primitives (DECISION D-014).

## Public surface (RF-011 scaffold)
- `restoflowBaseTheme()` - returns a neutral base `ThemeData` shell.

## Deferred
Real design tokens (colour, typography, spacing), shared widgets, and bidi
(RTL/LTR) layout primitives land in later UI tickets. **No feature/business UI
in RF-011.**
