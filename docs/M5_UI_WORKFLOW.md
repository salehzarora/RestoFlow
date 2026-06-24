# M5 UI Workflow — RestoFlow Demo UI Track

> **STATUS — ADVISORY / SUBORDINATE ADDENDUM.** This is an **operational
> addendum** for the **M5 "Usable Demo UI" track**, layered on top of the frozen
> [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md). It **does not replace** the Definition
> of Ready/Done, the Codex review step, or the human merge approval. If anything
> here conflicts with [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md), [../CLAUDE.md](../CLAUDE.md),
> or [DECISIONS.md](DECISIONS.md), **the frozen canon wins**.
>
> **M5 is not a formal milestone** (the frozen ladder is M0A–M4, DECISION
> **D-019**). M5 and the **RF-100+** range are a **working UI demo track created
> after** the original frozen plan. Making M5 a formal milestone, or entering
> RF-100+ into the backlog, is a **separate architecture / change-control
> decision** (new ticket + independent review + Saleh approval per
> [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9). Process changes here do **not**
> amend the frozen workflow.

---

## 1. Purpose

Define how M5 UI tickets are run day-to-day with a **reduced GitHub/PR cadence**,
while keeping every non-negotiable from [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md).
The companion [M5_UI_DIRECTION.md](M5_UI_DIRECTION.md) covers *what* to build and
the invariants it must respect.

## 2. Roles

| Role | Who | Responsibility in M5 |
|---|---|---|
| **Control room / planning** | ChatGPT | Frames tickets, scope, and acceptance; routes work. |
| **UI / docs implementer** | Claude Code | Plans (PLAN-ONLY), implements demo UI + docs, validates locally, reports. |
| **Reviewer / tester / scope guard** | Codex | Independent read-only review before any merge; catches scope creep, regressions, invariant violations. |
| **Final owner** | Saleh | Approves plans, approves each push/PR and each merge to `main`. Only Saleh merges. |

## 3. The M5 UI loop

```
PLAN-ONLY  →  Saleh approval  →  implementation  →  local validation
   →  local checkpoint commit  →  (repeat until a meaningful M5 chunk)
   →  Codex review  →  Saleh approval  →  push / PR / merge
```

1. **PLAN-ONLY** — for each UI ticket (RF-1xx), inspect first and return a plan
   (files, demo data, state, layout, l10n, tests, validation, out-of-scope,
   risks). No edits yet.
2. **Saleh approval** — wait for go before touching the tree.
3. **Implementation** — one ticket on one branch
   (`feat/RF-<id>-<slug>`), demo-first, invariants honoured (see
   [M5_UI_DIRECTION.md](M5_UI_DIRECTION.md)).
4. **Local validation** — run the §6 checklist; everything green locally.
5. **Local checkpoint commit** — commit locally (named per §5). **Allowed and
   encouraged. Do not push.**
6. **Repeat** small tickets/checkpoints until a **meaningful, validated M5 UI
   chunk** exists (see §4).
7. **Codex review** — independent review of the chunk; fix until APPROVE (no open
   Blocker/Major).
8. **Saleh approval → push/PR/merge** — Saleh authorises the push/PR; CI must be
   green; Saleh merges to `main`.

## 4. Reduced GitHub/PR cadence rules

- **Local checkpoint commits are OK and expected.** Commit early/often locally to
  keep safe restore points.
- **Do not push after every small ticket.** Avoid one PR per tiny change.
- **Push/PR only after a meaningful, locally-validated M5 UI chunk** — a coherent
  surface increment that **compiles, passes the §6 checklist, and runs in
  Chrome**. Examples of a "chunk": a dashboard screen reaching a demoable state;
  a KDS theme/tokens alignment pass; a cluster of related POS refinements.
- **What never relaxes at the push/PR boundary:**
  - **Codex review = APPROVE** (no open Blocker/Major) before merge.
  - **Saleh approval** for the push and for the merge — **only Saleh merges**.
  - **Green CI** at merge time.
  - **No autonomous pushes. No force-push (`--force`/`--force-with-lease`). No
    `git reset --hard`.** (Forbidden per [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md)
    §10.)
- **Checkpoint vs push validation:** a *checkpoint* needs **local green** (§6); a
  *push/PR* additionally needs **Codex APPROVE + green CI + Saleh approval**.
- Every unit of work still **anchors to a ticket** with scope + acceptance
  (Definition of Ready). RF-100+ are net-new and must be **defined before work**.

## 5. Branch & commit naming (reuse D-017)

- **Branch:** `feat/RF-<id>-<slug>` (types: `feat, fix, chore, docs, refactor,
  test, infra`).
- **Commit (Conventional Commits):** `<type>(<scope>): <summary> [RF-<id>]`.
- **Allowed UI scopes:** `pos`, `kds`, `dashboard`, `admin`, `design_system`,
  `l10n`, `docs`.
- Example: `feat(dashboard): add demo sales summary screen [RF-103]`.

## 6. Validation checklist for UI tickets (local "checkpoint DoD")

Run before each checkpoint commit (scope to what changed):

- [ ] `dart format .` — formatted (CI runs `--set-exit-if-changed`).
- [ ] `dart analyze .` — no issues.
- [ ] `flutter test <changed apps/packages>` — green (add/maintain tests for new UI).
- [ ] If strings changed: edit all three ARBs (en/ar/he), regenerate
      `AppLocalizations`, and run `flutter test packages/l10n` (ARB completeness).
- [ ] `bash tools/check_no_hardcoded_strings.sh` — no hardcoded app-shell strings.
- [ ] `bash tools/check_no_float_money.sh` — money stays integer minor units.
- [ ] `dart run tools/check_l10n.dart` — ARB + generated l10n consistent.
- [ ] `flutter build web` for the touched app — compiles for Chrome.
- [ ] Manual `flutter run -d chrome` — the change is visibly correct (incl. an
      RTL locale spot-check where relevant).
- [ ] Security/tenancy touch? If the change surfaces tenant-scoped or financial
      data, confirm role/tenant gating and keep the relevant isolation/permission
      tests (RISK **R-003/R-007**) — KDS must never show money.

## 7. Forbidden changes (in M5 UI tickets, unless a ticket explicitly approves)

- `supabase/**`, migrations, RLS policies, RPCs, DB schema.
- CI / GitHub Actions, production config, secrets, remote Supabase, `supabase
  link` / `db push`, deployment.
- Real `submit_order`, payments, auth/PIN, persistence, printing/hardware wiring.
- Frozen/governance docs: [../CLAUDE.md](../CLAUDE.md), [DECISIONS.md](DECISIONS.md),
  [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md), [PROJECT_PLAN.md](PROJECT_PLAN.md),
  [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md),
  [JIRA_IMPORT.csv](JIRA_IMPORT.csv), and (in a docs step) [TASK_TRACKER.md](TASK_TRACKER.md)
  unless the ticket is specifically for them.
- Floating-point money anywhere. Hardcoded user-facing strings in app shells.
- Pushing/merging without Saleh approval; force-push; history rewrites.

## 8. What to report after each ticket / checkpoint

Keep reports short and concrete:

1. **Branch name** and ticket id.
2. **Files changed** (created/modified).
3. **What is visible now** (the user-facing result; Chrome-runnable).
4. **Validation run** — exact commands and results (the §6 checklist).
5. **Scope confirmation** — no backend/Supabase/migration/RLS/RPC/schema/CI/
   production/secrets changes; no frozen-doc edits; money still integer-minor.
6. **Working tree state** — clean or not; whether a local checkpoint commit was
   made (and its hash) vs. left uncommitted.
7. **Push/PR status** — confirm **not pushed** unless Saleh authorised a chunk
   push (then: Codex verdict + CI status + commit/PR reference).

---

> Companion: [M5_UI_DIRECTION.md](M5_UI_DIRECTION.md) (what to build + invariants).
> Authority: [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) (frozen pipeline this addendum
> sits under).
