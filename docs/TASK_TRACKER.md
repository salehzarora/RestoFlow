# TASK_TRACKER.md — Session Resume Pointer

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> Concise session-resume file only. **NOT** a backlog. The master task list lives in
> [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) ([JIRA_IMPORT.csv](JIRA_IMPORT.csv) is a historical export only — **DECISION D-038**).

| Field | Value |
| --- | --- |
| Work-ID scheme | Approved Work IDs (**DECISION D-038**, GOV-001). Jira is no longer used; `RF` is the historical ticket prefix and is never renumbered. |
| Current milestone | M7 real-wiring → **BIZBOT-PAYMENTS-ZCREDIT-PILOT-001** (card-present POS payments pilot, docs first; **DECISION D-051** / **D-052** / **D-053** / **D-054** / **D-055** / **D-056**) |
| Active ticket | `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B` — provider contract (docs only: [API_CONTRACT](API_CONTRACT.md) §4.55 + §4.7 / §4.7a / §4.14 / §4.30b / §4.30c / §4.33 / §4.35 notes, DOMAIN_MODEL §8.4 / §8.5, OFFLINE_SYNC §10.1, TESTING_STRATEGY §6, DEPLOYMENT §18, RUNBOOKS §8, OPERATIONS §3.2 / §3.3, **D-053** / **D-054** / **D-055** / **D-056**, Q-051 / Q-053..Q-057 resolved); 001A (D-051 / D-052 / Q-047..Q-056) precedes it |
| Status | H0 vendor-material housekeeping done locally on 2026-10-21 (no tracked change). PR **#362** (001A → `main`) and PR **#363** (001B → the 001A branch, stacked) are open **Draft** PRs with auto-merge OFF. #362 at `96fd9597` (synchronized with `main` `ec134ded`; `main` has since moved to `fe78bbcd` through Storefront-only PRs #365 / #367 with no overlap and no conflict) received APPROVE_WITH_NONBLOCKING_NOTES in the final review of 2026-10-22; that review ran in Claude Code, so the independent Codex gate remains open. #363 received REQUEST_CHANGES (one blocker, seven majors) and correction round 4 (**D-056**) answers it in one additive docs-only commit; its CI runs once pushed. Neither PR is approved for merge; 001D remains **blocked** |
| Branch | `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B-provider-contract` (PR #363, Draft) stacked on `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A-design` (PR #362, Draft); worktrees `worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A` / `…-001B` |
| Primary agent | Claude Code |
| Reviewer | Codex |
| Next step | The true independent Codex read-only review of #362 (against `main`) and of the round-4 #363 (against the exact #362 head); separate merge approval for #362 (merge commit, not squash); retarget #363 to `main`, reverify its incremental diff, re-run CI and the exact-head review, separate merge approval; only then an exact-scope approval for 001D (private ledger / RLS / RPCs / `sync_push` guard) → 001E → 001C → 001F per the packet |
| Current blockers | None for 001A / 001B (docs). 001D is not authorized until both PRs merge and the owner approves its exact scope; the physical test waits for deploy-with-flags-OFF, the owner-approved TEST secret setup and the owner-approved test-card run (packet §8) |
| Last verification | Docs-only change: CRLF preserved per file; every literal anchor matched exactly once; no secret, credential, identifier, device UUID or vendor value; `tools/check_secrets.sh` run in the 001B worktree before commit; contradiction sweeps for every round-4 token; CI green on the 001A head `96fd9597` (run 39684246629) and on the round-3 001B head `b787344a` (run 39701706869); the round-4 head has no run until pushed |

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
