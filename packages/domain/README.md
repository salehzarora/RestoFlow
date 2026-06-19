# restoflow_domain

Domain **entity & value-object foundations** (a.k.a. the `models` package in the
checklist's older wording). Pure Dart - no Flutter, no IO.

Per [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) section 3 this package will own
entities, value objects, the PROPOSED state enumerations (DECISION D-018), and
pure domain rules.

## Public surface (RF-011 scaffold)
- `Entity` - neutral marker for an identity-bearing domain object.

## Money
This package does **not** define a money type. The integer minor-unit money
type lives in `packages/money` (ticket **RF-036**) per **DECISION D-007** and
ARCHITECTURE section 3; domain entities will hold money-typed fields *backed by*
that package. No floating-point money anywhere (enforced by
`tools/check_no_float_money.sh`).

## Deferred
Concrete entities (RF-014 orgs/restaurants/branches, RF-030 menu) and the order/
payment **state machines** (RF-032) land in their own tickets. **No business
logic in RF-011.**
