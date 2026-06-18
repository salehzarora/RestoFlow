# AGENTS.md — RestoFlow Multi-Agent Governance Contract

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [docs/DECISIONS.md](docs/DECISIONS.md) and [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md).

This is the short, binding contract that **Claude Code** and **Codex** read before
doing any work on RestoFlow. It encodes the agent workflow (**DECISION D-016**),
the sources of truth (**DECISION D-015**), and the hard guardrails that keep a
single-builder, multi-AI team safe (mitigates **RISK R-005** single-builder bus
factor and protects **RISK R-003** RLS correctness).

> This file is intentionally tight. It is the *quick contract*.
> [docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md) is **authoritative** for the
> Definition of Ready (DoR), Definition of Done (DoD), report formats, merge
> gates, and the architecture-change procedure. When this file and
> AGENT_WORKFLOW.md disagree on process detail, AGENT_WORKFLOW.md wins; when any
> document conflicts with the SHARED CANON or [docs/DECISIONS.md](docs/DECISIONS.md),
> the canon and DECISIONS.md win.

---

## 1. Roster and responsibilities

RestoFlow is built by **1 human + 3 AI agents**. Each actor has a single, clear
mandate. No actor may silently assume another's authority.

| Actor | Mandate | Must NOT |
|---|---|---|
| **Human — Saleh** (owner) | Final decision-maker. Approves plans and prompts, reviews output, performs the **merge**, gives **RLS + security sign-off** (mandatory, see **RISK R-003**, [docs/SECURITY_AND_THREAT_MODEL.md](docs/SECURITY_AND_THREAT_MODEL.md)), and is the only on-site actor for **hardware** (printers, cash drawer, POS/KDS devices — see **OPEN QUESTION Q-006**, [docs/PRINTERS_AND_HARDWARE_SPEC.md](docs/PRINTERS_AND_HARDWARE_SPEC.md)). Owns decisions in [docs/DECISIONS.md](docs/DECISIONS.md). | Skip security sign-off; delegate the merge gate to an AI. |
| **ChatGPT** (planning layer) | Planning, option analysis, trade-off framing, and drafting prompts/tickets for human approval. Helps shape decisions and open questions before implementation. | Write production code, edit the repo, or freeze a decision unilaterally. |
| **Claude Code** (implementer) | Primary implementer: writes code, migrations (when ticketed), and **tests**. Produces an implementation report per the format in AGENT_WORKFLOW.md. Operates on its own branch/worktree. | Push, merge, edit the same worktree as Codex, or expand scope silently. |
| **Codex** (reviewer) | Independent, **read-only by default** review of Claude Code's changes. May execute a *separate* assigned task **on its own branch + worktree** when explicitly ticketed. Produces a review report. | Edit Claude Code's active worktree; approve its own merge; push or merge. |
| **Git** | Final arbiter and **source of truth for code and change history** (**DECISION D-015**). | — |

Supporting sources of truth (**DECISION D-015**): **Jira** (project key `RF`) =
task status; **architecture docs in `docs/`** = technical decisions and contracts;
[docs/TASK_TRACKER.md](docs/TASK_TRACKER.md) = concise current-session resume only (never a duplicate backlog).

---

## 2. Workflow pipeline (DECISION D-016)

Ordered, every ticket follows it:

1. **ChatGPT planning** — options, trade-offs, draft prompt/ticket.
2. **Human approval** — Saleh approves the plan/prompt and the ticket reaches DoR.
3. **Claude Code implementation** — code + migrations (if ticketed) on its own branch.
4. **Tests** — Claude Code writes/extends tests; suite + analysis pass.
5. **Codex independent review** — read-only review against DoD and contracts.
6. **Claude Code fixes** — address Changes Requested.
7. **Human approval** — Saleh reviews; **RLS/security sign-off** where relevant.
8. **Merge** — Saleh merges. Only the human merges.

Jira state flow (recommended): `Backlog -> Ready -> In Progress -> Code Review ->
Changes Requested -> Ready for Merge -> Done`; plus `Blocked`, `Deferred`,
`Cancelled`.

---

## 3. Permissions matrix

Mirrors the v1.0 plan. Applies to **both** AI agents unless stated.

### Allowed automatically (no approval needed)
- Read any repo file; edit files **within the active ticket's scope**.
- Run tests, static analysis, type checks, formatters, and local builds.
- Create local commits on the **ticket's own branch** (Conventional Commits:
  `<type>(<scope>): <summary> [RF-<id>]`, per **DECISION D-017**).
- Create the ticket branch: `<type>/RF-<id>-<slug>`, `type ∈ {feat,fix,chore,docs,refactor,test,infra}`.

### Ask-first (requires human approval before acting)
- Add or upgrade a **dependency** / package.
- Apply a **database migration** (incl. any RLS-affecting change — **RISK R-003**).
- Edit **API contracts** or **shared packages** — these need a *dedicated ticket*
  (see [docs/API_CONTRACT.md](docs/API_CONTRACT.md)).
- Any **architecture change** — follow the procedure in AGENT_WORKFLOW.md; record
  in [docs/DECISIONS.md](docs/DECISIONS.md).

### Forbidden (never, without explicit human action by Saleh)
- `git push` of any kind, and **force push** (`--force` / `--force-with-lease`).
- `git reset --hard`.
- `supabase db reset` or any database reset.
- **Delete or destroy real data**; remove tombstoned/audit rows
  (**DECISION D-013** audit events are append-only and never deletable by app roles;
  **DECISION D-020** deletions are tombstones, not hard deletes).
- Read, print, log, or expose **secrets**. **SECURITY REQUIREMENT**: no
  service-role credentials in clients or commits; no shared restaurant password.
- Any **production** change or deploy.
- **Silent scope expansion** beyond the ticket.

> **ASSUMPTION**: M0A is **documentation only**. No code, migrations, package
> manifests, CI, or Supabase setup are produced in this milestone (**DECISION D-019**).
> The "ask-first" migration/dependency rows above are forward-looking and apply
> from **M0B** onward.

---

## 4. Concurrency rules

- **Claude Code and Codex must never edit the same working tree at the same time.**
- **One active ticket per worktree.**
- Parallel work requires **separate branches + separate worktrees** — never two
  agents in one tree.
- Codex reviews **read-only by default**; it only writes when running its own
  separately ticketed task in its own worktree.

---

## 5. Every task needs a ticket ID

No work — code, migration, contract edit, or doc change — happens without a
**ticket `RF-<number>`** (this M0A documentation set, proposed for the architecture freeze pending review and approval, is **RF-001**). Branches,
commits, and reports all carry the ticket ID. Shared-package and API-contract
changes get their **own dedicated tickets** (Section 3, ask-first).

---

## 6. Pointer to the authoritative process

For anything not fully specified here — **DoR / DoD checklists, implementation
and review report formats, merge gates, and the architecture-change procedure** —
[docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md) is authoritative. This file does
not duplicate that process; it references it.

Related: [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) (milestones/ownership),
[docs/DECISIONS.md](docs/DECISIONS.md) (decision log),
[docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md) (open-questions register).
