# TASK_TRACKER.md — Session Resume Pointer

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> Concise session-resume file only. **NOT** a backlog. The master task list lives in
> [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) and [JIRA_IMPORT.csv](JIRA_IMPORT.csv).

| Field | Value |
| --- | --- |
| Jira project key | RF |
| Current milestone | M7 real-wiring → **product-rescue sprint** (visible local MVP) |
| Active ticket | Product-rescue sprint (owner-directed, unticketed by owner instruction): visible dashboard/POS/KDS MVP over the RF-150..161 foundation |
| Status | Sprint implemented on `feature/product-rescue-visible-mvp` — launch fix (supabase_flutter passkeys crash), setup center + Printers/Staff surfaces, staff/PIN provisioning (bcrypt production verifier), device-originated PIN sign-in, real POS menu/order/payment loop, KDS order.status persistence, sales_summary Overview, CI coverage expansion |
| Branch | `feature/product-rescue-visible-mvp` (off main @ RF-161 merge; NOT pushed) |
| Primary agent | Claude Code |
| Reviewer | Codex |
| Next step | Human review of the sprint branch; mandatory RLS/security sign-off (AGENTS.md) before real tenant data; then PR per owner decision |
| Current blockers | Human RLS/security sign-off outstanding (hard gate); hardware print transports human-gated (Q-006/Q-015) |
| Last verification | pgTAP 164 files / 2508 assertions PASS (includes the 6 sprint suites + bcrypt fixture conversions); `dart analyze apps packages` clean; full Flutter suites + guards run in the sprint's final validation (see LOCAL_RUNBOOK.md §11) |

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
