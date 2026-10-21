# TASK_TRACKER.md — Session Resume Pointer

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> Concise session-resume file only. **NOT** a backlog. The master task list lives in
> [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) ([JIRA_IMPORT.csv](JIRA_IMPORT.csv) is a historical export only — **DECISION D-038**).

| Field | Value |
| --- | --- |
| Work-ID scheme | Approved Work IDs (**DECISION D-038**, GOV-001). Jira is no longer used; `RF` is the historical ticket prefix and is never renumbered. |
| Current milestone | M7 real-wiring → **BIZBOT-PAYMENTS-ZCREDIT-PILOT-001** (card-present POS payments pilot, docs first; **DECISION D-051** / **D-052**) |
| Active ticket | `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B` — provider contract (docs only: [API_CONTRACT](API_CONTRACT.md) §4.55 + §4.7 / §4.7a / §4.14 / §4.30b / §4.30c / §4.33 / §4.35 notes, DOMAIN_MODEL §8.4 / §8.5, OFFLINE_SYNC §10.1, TESTING_STRATEGY §6, DEPLOYMENT §18, RUNBOOKS §8, OPERATIONS §3.2 / §3.3); 001A (D-051 / D-052 / Q-047..Q-056) precedes it |
| Status | H0 vendor-material housekeeping done locally on 2026-10-21 (no tracked change); 001A and 001B written on stacked branches from `origin/main` `e9aec540`; NOT pushed |
| Branch | `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B-provider-contract` stacked on `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A-design` (worktrees `worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A` / `…-001B`; NOT pushed) |
| Primary agent | Claude Code |
| Reviewer | Codex |
| Next step | Owner approval to push both branches and open the PRs (001B targets 001A, then main); Codex read-only review; merge in order; then 001D (private ledger / RLS) → 001E (Edge adapter) → 001C → 001F per the packet |
| Current blockers | None for 001A / 001B (docs). Code tickets wait for the 001A / 001B merges; the physical test waits for deploy-with-flags-OFF, the owner-approved TEST secret setup and the owner-approved test-card run (packet §8) |
| Last verification | Docs-only change: CRLF preserved per file; every literal anchor matched exactly once; no secret, credential, identifier or vendor value; `tools/check_secrets.sh` run in the worktree before commit |

## Authoritative references

- [PROJECT_PLAN.md](PROJECT_PLAN.md)
- [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md)
- [JIRA_IMPORT.csv](JIRA_IMPORT.csv) — historical export only (**DECISION D-038**)
- [DECISIONS.md](DECISIONS.md)
- [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md)

---

**Reminder:** Per **DECISION D-015** as amended by **DECISION D-038** (GOV-001), the GitHub PR / branch state is the source of truth for the status of active work and [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) is the planned-work list; this file is only a resume pointer and never a duplicate backlog.
