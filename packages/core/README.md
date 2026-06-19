# restoflow_core

Cross-cutting **foundations** shared across the RestoFlow monorepo. Pure Dart -
**no Flutter, no IO, no POS/restaurant business rules**.

Owns (per [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) section 3): Result/error
types, environment selection, and logging hooks.

## Public surface (RF-011 scaffold)
- `Result<S, F>` (`Success` / `Failure`) - neutral functional result type.
- `AppEnvironment` - `dev` / `staging` / `prod` selector (carries **no**
  URLs/keys/secrets; values are injected at runtime - DECISION D-011).
- `RestoLogger` + `LogLevel` - logging hook interface (implementations must
  redact secrets and log money only as integer minor units).

## Dependency direction
`core` depends on nothing app-specific; other packages may depend on `core`.

## Deferred
Concrete utilities are added as later tickets need them. **No business logic,
no money type** (the integer minor-unit money type lives in `packages/money`,
ticket RF-036 - DECISION D-007).
