# WEB-ORDERS-CHECKOUT-001 — owner-approved execution packet

Baseline: `59f3eb5976b8f8cfa52e61ddc475464b3ede6f0e` (PR #322 Normal Merge).
Branch: `feat/WEB-ORDERS-CHECKOUT-001-checkout`.
Decision authority: GPT + project owner; Codex is the sole executor.

## Approval and scope

Owner authorization on 2026-10-14 explicitly approves direct browser HTTPS POST
only to the configured Supabase `web-order-submit` endpoint, a CSP exception for
that exact origin, capability-only tab-session recovery, and backward-compatible
per-item notes across HTTP validation, SQL snapshots/revalidation and POS
acceptance. No Next.js API routes, generic proxies, new dependencies, online
payment, delivery, or visual redesign.

Recovery may persist only canonical slug, UUIDv4 request ID, a Web Crypto
256-bit capability and creation/expiry metadata, for at most 24 hours. Customer,
cart, modifiers, notes and the frozen submission payload remain memory-only.
After uncertain submission, reconcile status before an explicit retry with the
same ID/token/body. After reload without the body, recover status only.

Notes must remain distinct per line, bounded and validated without truncation;
order notes remain independent. Canonical order writer and KDS/printer engines
are unchanged. Submission creates pending requests only; trusted POS acceptance
is the sole canonical-order boundary.

## Isolation and verification

Fresh origin/main verified. PR #314/#315 and dirty worktrees have zero exact
file overlap with the planned checkout, Edge validation and inbox-note scope.
Parallel Codex subtasks use separate branches/worktrees. Primary checkout and
Claude Code workstreams are not edited.

Focused checks cover payload/price authority, modifiers/quantities/notes,
identity/retry/reload recovery, capability/tenant isolation, terminal states,
no premature/duplicate canonical or kitchen dispatch, accepted canonical notes,
AR/HE/EN responsive UI, exact CSP, credential and storage boundaries. One
independent review and normal GitHub CI follow implementation.

## Activation and release boundary

Live Storefront remains browse-only. No hosted migrations, Edge deployment,
real customer test orders, channel/ordering/delivery changes, production
configuration changes, merges or production deployment are authorized. The PR
contains source/configuration for separately approved future activation only.
Hosted dependencies: WEB-ORDERS-001, POS-ONLINE-INBOX-001 and this task's additive
migration; compatible web-order-submit deployment; separate rollout approval.

Implementation results and exact scope will be added after focused verification.
