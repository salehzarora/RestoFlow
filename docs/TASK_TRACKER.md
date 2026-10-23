# TASK_TRACKER.md — Session Resume Pointer

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> Concise session-resume file only. **NOT** a backlog. The master task list lives in
> [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) ([JIRA_IMPORT.csv](JIRA_IMPORT.csv) is a historical export only — **DECISION D-038**).

| Field | Value |
| --- | --- |
| Work-ID scheme | Approved Work IDs (**DECISION D-038**, GOV-001). Jira is no longer used; `RF` is the historical ticket prefix and is never renumbered. |
| Current milestone | M7 real-wiring → **BIZBOT-PAYMENTS-ZCREDIT-PILOT-001** (card-present POS payments pilot, docs first; **DECISION D-051** / **D-052** / **D-053** / **D-054** / **D-055** / **D-056** / **D-057** / **D-058**) |
| Active ticket | `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B` — provider contract (docs only: [API_CONTRACT](API_CONTRACT.md) §4.55 + §4.7 / §4.7a / §4.14 / §4.30b / §4.30c / §4.33 / §4.35 notes, DOMAIN_MODEL §8.4 – §8.7, OFFLINE_SYNC §10.1, TESTING_STRATEGY §6, DEPLOYMENT §18, RUNBOOKS §8, OPERATIONS §3.2 / §3.3, **D-053** / **D-054** / **D-055** / **D-056** / **D-057** / **D-058**, Q-051 / Q-053..Q-057 resolved); 001A (D-051 / D-052 / Q-047..Q-056, amended in place in round 6) precedes it |
| Status | H0 vendor-material housekeeping done locally on 2026-10-21 (no tracked change). PR **#362** (001A → `main`) and PR **#363** (001B → the 001A branch, stacked) are open **Draft** PRs with auto-merge OFF. Correction round 6 (2026-10-23) answers the existing independent Codex review of the exact heads #362 `96fd9597` / #363 `285d52f1` (its findings as summarized by the command room; one blocker): the 001A commit amended **D-051** / **D-052** in place (the hard non-settlement gate, full-identity provider keys, no provider free text, the Android POS normative, the exact Dashboard exception); that head is merged here by a normal merge commit; the 001B commit records **DECISION D-058** (the shared identity and terminal admission locks, the pre-ledger TEST refusal, the physical TEST procedure, the service-only `free_order`, field-specific no-card-data validation, the explicit Resume comparison with the two-path parse, the private-event wording) with dated notes on **D-051**..**D-057**. Neither PR is approved for merge; 001D remains **blocked** |
| Branch | `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001B-provider-contract` (PR #363, Draft) stacked on `docs/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A-design` (PR #362, Draft); worktrees `worktrees/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001A` / `…-001B` |
| Primary agent | Claude Code |
| Reviewer | Codex (independent; **D-016**, [AGENT_WORKFLOW](AGENT_WORKFLOW.md) §8 merge gate 4 and §9 step 4). The Claude Code read-only reviews of 2026-10-22 / 23, run on the command room's instruction, are additional reviews and do not satisfy gate 4; changing that gate needs its own Work ID and a recorded decision under the architecture-change procedure |
| Next step | The final Claude Code read-only review of both round-6 heads (#362 against `main`, #363 against the exact #362 head), on the command room's instruction. Merge gate 4 (**D-016**; [AGENT_WORKFLOW](AGENT_WORKFLOW.md) §2.1 stage 6, §8 gate 4, §9 step 4), unchanged: the Codex review of the round-5 heads is answered by round 6, and the gate requires a Codex review with verdict APPROVE of the exact round-6 heads (**D-058** included) before merge; the owner's instruction to rely on Claude Code reviews conflicts with that gate and is surfaced for an owner decision under its own Work ID — this ticket changes neither **D-016** nor [AGENT_WORKFLOW](AGENT_WORKFLOW.md). Then separate merge approval for #362 (merge commit, not squash); retarget #363 to `main`, reverify its incremental diff, re-run CI and the exact-head review, separate merge approval; only then an exact-scope approval for 001D tied to the #363 merge commit → 001E → 001C → 001F per the packet |
| Current blockers | None for 001A / 001B (docs). Every real provider action is blocked until the owner seals the **Q-047** non-settling TEST facility evidence and the **Q-049** key-format evidence (**D-051** point 7, **D-052** point 2); 001D is not authorized until both PRs merge and the owner approves its exact scope |
| Last verification | Docs-only change: CRLF preserved per file; every literal anchor matched exactly once; no secret, credential, identifier, device UUID, card data or vendor value; `tools/check_secrets.sh` run before commit; contradiction sweeps for every round-6 token; a four-lens Claude Code verification (coverage, consistency, soundness, security) with skeptic confirmation of each major, then a two-lens confirmation pass and a final consistency check of the fix batches, their findings applied before commit; CI runs on the pushed heads |

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
