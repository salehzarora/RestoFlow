# TASK_TRACKER.md — Session Resume Pointer

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> Concise session-resume file only. **NOT** a backlog. The master task list lives in
> [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) ([JIRA_IMPORT.csv](JIRA_IMPORT.csv) is a historical export only — **DECISION D-038**).

| Field | Value |
| --- | --- |
| Work-ID scheme | Approved Work IDs (**DECISION D-038**, GOV-001). Jira is no longer used; `RF` is the historical ticket prefix and is never renumbered. |
| Current milestone | M7 real-wiring → **BIZBOT-PAYMENTS-ZCREDIT-PILOT-001** (card-present POS payments pilot, docs first; **DECISION D-051** / **D-052** / **D-053** / **D-054** / **D-055**) |
| Active ticket | `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B` — provider contract (docs only: [API_CONTRACT](API_CONTRACT.md) §4.55 + §4.7 / §4.7a / §4.14 / §4.30b / §4.30c / §4.33 / §4.35 notes, DOMAIN_MODEL §8.4 / §8.5, OFFLINE_SYNC §10.1, TESTING_STRATEGY §6, DEPLOYMENT §18, RUNBOOKS §8, OPERATIONS §3.2 / §3.3, **D-053** / **D-054** / **D-055**, Q-051 / Q-053..Q-057 resolved); 001A (D-051 / D-052 / Q-047..Q-056) precedes it |
| Status | H0 vendor-material housekeeping done locally on 2026-10-21 (no tracked change). PR **#362** (001A → `main`) and PR **#363** (001B → the 001A branch, stacked) are open **Draft** PRs. 2026-10-22: the 001A branch was synchronized with `main` `ec134ded` (PRs #361 / #364) by a merge commit resolving the `docs/DECISIONS.md` append-adjacency conflict (head `96fd9597`), and the updated 001A was merged into 001B; #363 then received the command-room review round 2 (**D-054** recording recovery, standing-charge policy, mode-aware credentials, exact money serialization, provider-only free-order evidence) and the final independent review round 3 (**D-055** frozen shift / drawer context, shift-close exclusion, canonical lock order; no persisted free-text provider message). The final independent review of 2026-10-22 returned APPROVE_WITH_NONBLOCKING_NOTES for #362 and REQUEST_CHANGES for #363; the round-3 correction answers it and the final Codex approval pass runs on the corrected final heads. #362 at `96fd9597` is MERGEABLE / CLEAN with green CI (run 39684246629); the #363 round-2 head's CI runs once pushed; the #362 command-room content review passed on 2026-10-21 pending the independent Codex review; #363 remains unapproved for merge until its independent review and the owner's separate merge approval; 001D remains **blocked** |
| Branch | `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B-provider-contract` (PR #363, Draft) stacked on `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A-design` (PR #362, Draft); worktrees `worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A` / `…-001B` |
| Primary agent | Claude Code |
| Reviewer | Codex |
| Next step | Independent Codex read-only review of #362 (against `main`) and of the corrected #363 (against the exact #362 head); separate merge approval for #362 (merge commit, not squash); retarget #363 to `main`, reverify its incremental diff, re-run CI and the exact-head review, separate merge approval; only then an exact-scope approval for 001D (private ledger / RLS / RPCs / `sync_push` guard) → 001E → 001C → 001F per the packet |
| Current blockers | None for 001A / 001B (docs). 001D is not authorized until both PRs merge and the owner approves its exact scope; the physical test waits for deploy-with-flags-OFF, the owner-approved TEST secret setup and the owner-approved test-card run (packet §8) |
| Last verification | Docs-only change: CRLF preserved per file; every literal anchor matched exactly once; no secret, credential, identifier, device UUID or vendor value; `tools/check_secrets.sh` run in both worktrees before commit; Storefront content of PRs #361 / #364 preserved unchanged; CI green on the pushed 001A head `96fd9597` (run 39684246629); the synchronized 001B head and the round-2 edits have no run until pushed |

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
