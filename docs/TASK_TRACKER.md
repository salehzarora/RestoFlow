# TASK_TRACKER.md — Session Resume Pointer

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> Concise session-resume file only. **NOT** a backlog. The master task list lives in
> [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) ([JIRA_IMPORT.csv](JIRA_IMPORT.csv) is a historical export only — **DECISION D-038**).

| Field | Value |
| --- | --- |
| Work-ID scheme | Approved Work IDs (**DECISION D-038**, GOV-001). Jira is no longer used; `RF` is the historical ticket prefix and is never renumbered. |
| Current milestone | M7 real-wiring → **BIZBOT-PAYMENTS-ZCREDIT-PILOT-001** (card-present POS payments pilot, docs first; **DECISION D-051** / **D-052**) |
| Active ticket | `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A` — design and decision packet (docs only: D-051, D-052, Q-047..Q-056, scope carve-out, canon annotations, [BIZBOT_PAYMENTS_ZCREDIT_PILOT_001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md)) |
| Status | H0 vendor-material housekeeping done locally on 2026-10-21 (no tracked change). PR **#362** (001A → `main`) and PR **#363** (001B → the 001A branch, stacked) are open **Draft** PRs; the 001A branch carries the merge of current `main` (`ec134ded`, PRs #361 / #364) with the `docs/DECISIONS.md` append-adjacency conflict resolved by keeping both blocks; CI runs on the synchronized heads; the #362 command-room content review passed on 2026-10-21 pending the independent Codex review; #363 remains unapproved for merge; 001D remains **blocked** |
| Branch | `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B-provider-contract` (PR #363, Draft) stacked on `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A-design` (PR #362, Draft); worktrees `worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A` / `…-001B` |
| Primary agent | Claude Code |
| Reviewer | Codex |
| Next step | Independent Codex read-only review of #362 (against `main`) and of #363 (against the exact #362 head); separate merge approval for #362 (merge commit, not squash); retarget #363 to `main`, reverify its incremental diff, re-run CI and the exact-head review, separate merge approval; only then an exact-scope approval for 001D (private ledger / RLS) → 001E (Edge adapter) → 001C → 001F per the packet |
| Current blockers | None for 001A / 001B (docs). 001D is not authorized until both PRs merge and the owner approves its exact scope; the physical test waits for deploy-with-flags-OFF, the owner-approved TEST secret setup and the owner-approved test-card run (packet §8) |
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
