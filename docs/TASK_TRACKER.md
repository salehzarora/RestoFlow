# TASK_TRACKER.md — Session Resume Pointer

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> Concise session-resume file only. **NOT** a backlog. The master task list lives in
> [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) and [JIRA_IMPORT.csv](JIRA_IMPORT.csv).

| Field | Value |
| --- | --- |
| Jira project key | RF |
| Current milestone | M0A |
| Active ticket | RF-003 — Resolve Approved RF-002 Findings & Prepare the Architecture Freeze Candidate |
| Status | In Progress |
| Branch | (none yet — M0A is docs-only, not committed) |
| Primary agent | Claude Code |
| Reviewer | Codex |
| Next step | Final Codex read-only re-verification of the RF-003 cleanup, then RF-004 human approval / freeze event |
| Current blockers | none (RF-001 done; RF-002 complete — APPROVE WITH CHANGES; RF-003 Codex verification returned CHANGES REQUESTED, now applied) |
| Last verification | RF-003 cleanup applied after Codex CHANGES-REQUESTED: B-001 open-question gate (Q-001..Q-024 set to **Accepted Open** per **DECISION D-027** — none resolved/guessed), B-002 dangling branch/commit examples repointed to existing tickets (RF-054, RF-036), N-001 README decision range → D-001..D-028, plus `.claude/` added to `.gitignore`. Earlier RF-003 content corrections (payment/order terminal rules, platform-admin separation, accountant read-only, shift split) stand — pending final Codex re-verification + Saleh approval (RF-004 freeze event) |

## Authoritative references

- [PROJECT_PLAN.md](PROJECT_PLAN.md)
- [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md)
- [JIRA_IMPORT.csv](JIRA_IMPORT.csv)
- [DECISIONS.md](DECISIONS.md)
- [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md)

---

**Reminder:** Per **DECISION D-015**, Jira (project key RF) is the source of truth for task status; this file is only a resume pointer.
