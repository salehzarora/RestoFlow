# AGENT_WORKFLOW.md — RestoFlow Agent Workflow (Authoritative)

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> **Ownership.** This document is the single authoritative source for the **RestoFlow agent workflow and engineering process**: the delivery pipeline, Definition of Ready, Definition of Done, branch/commit naming, the implementation- and review-report formats, merge gates, the architecture-change procedure, and the concurrency/worktree rules plus forbidden-actions list. `AGENTS.md` (repo root) is the **concise pointer** to this document, not a second source of truth. This document implements and elaborates **DECISION D-016** (agent workflow pipeline + guardrails); it does **not** redefine the decision log ([DECISIONS.md](DECISIONS.md)), the open-question register ([OPEN_QUESTIONS.md](OPEN_QUESTIONS.md)), naming conventions beyond what process requires (**DECISION D-017**), the test strategy ([TESTING_STRATEGY.md](TESTING_STRATEGY.md)), security/isolation tests ([SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)), or the task backlog ([IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) + JIRA_IMPORT.csv). Those topics are referenced, not restated.
>
> **Status.** Drafted as part of milestone **M0A** (**DECISION D-019**, ticket **RF-001**); frozen as the M0A architecture baseline at RF-004, approved into the frozen M0A baseline (RF-004). Changes to this process require a new decision in [DECISIONS.md](DECISIONS.md) and human approval (see §8 and §10).

---

## 1. Purpose and team

RestoFlow is a **multi-tenant Restaurant Operating System** serving many independent restaurant customers on one platform (**DECISION D-001**, **DECISION D-002**, **DECISION D-003**). It is built by a small team using a **documentation-and-architecture-first** method ("freeze before code"):

| Actor | Role in the pipeline |
| --- | --- |
| **Human owner (Saleh)** | Final decision authority. Approves plans, approves merges, owns all guardrails. The only actor permitted to authorize pushes, merges, and any forbidden action (§9). |
| **ChatGPT** | Planning / design layer. Produces tickets, scope, acceptance criteria, and design proposals for review by the human. |
| **Claude Code** | Primary implementer. Writes code, migrations, and tests; produces the **implementation report** (§5). |
| **Codex** | Independent reviewer. Reviews **read-only by default** and produces the **review report** (§6). Does not implement on the same working tree as Claude Code (§9). |

**RISK R-005** (single-builder bus factor): every decision and change is documented; Codex provides independent review; Git is the source of truth for code (**DECISION D-015**). This workflow is the primary mitigation.

This document does not assume a single restaurant or organization at any stage; the tenant is the **Organization** (**DECISION D-003**).

---

## 2. The delivery pipeline (DECISION D-016)

Every change flows through this pipeline in order. No stage may be skipped. Each stage has a defined **input gate** and a defined **output artifact**.

```
ChatGPT planning
   -> Human approval (plan)
      -> Claude Code implementation
         -> Tests (written + passing)
            -> Codex independent review
               -> Claude Code fixes (loop until clean)
                  -> Human approval (merge)
                     -> Merge
```

### 2.1 Stage table

| # | Stage | Performed by | Input gate | Output artifact |
| --- | --- | --- | --- | --- |
| 1 | **Planning** | ChatGPT + human | A need exists (milestone, bug, contract change) | A ticket (RF-`<id>`) with scope + acceptance criteria + dependency + architecture/security-impact note, recorded in Jira (**DECISION D-015**) and traceable to [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) |
| 2 | **Plan approval** | Human owner | Ticket drafted | Ticket meets **Definition of Ready** (§3); moved to **Ready** in Jira |
| 3 | **Implementation** | Claude Code | Ticket is Ready; branch + worktree assigned | Code + migrations (where in milestone scope; **never in M0A**, §9) on the ticket branch |
| 4 | **Tests** | Claude Code | Implementation drafted | Tests written and passing, including **mandatory isolation/permission tests** where relevant ([SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [TESTING_STRATEGY.md](TESTING_STRATEGY.md)); the **implementation report** (§5) |
| 5 | **Independent review** | Codex | Implementation report exists; branch pushed to a review location with human approval, or reviewed in a read-only worktree | The **review report** (§6) with a verdict |
| 6 | **Fixes** | Claude Code | Review report = changes-requested | Updated code/tests + an updated implementation report; loops back to stage 5 until verdict = approve |
| 7 | **Merge approval** | Human owner | Review verdict = approve; all **merge gates** (§7) green | Human authorization to merge |
| 8 | **Merge** | Human owner (Saleh) | Merge approved | Merged to `main`; ticket -> **Done** in Jira; branch retired |

> **ASSUMPTION.** The default working branch is `main` (repo state at M0A). The protected target branch for merges is `main` unless a release-branch model is later adopted via a new decision in [DECISIONS.md](DECISIONS.md).

### 2.2 Jira workflow states (recommended mapping)

The pipeline maps to the Jira state machine (**DECISION D-015**; CSV import must work on free Jira, no paid-only features):

```
Backlog -> Ready -> In Progress -> Code Review -> Changes Requested -> Ready for Merge -> Done
              (+ Blocked, Deferred, Cancelled as off-ramps)
```

- **Backlog -> Ready**: ticket passes Definition of Ready (§3).
- **Ready -> In Progress**: Claude Code starts implementation (stage 3).
- **In Progress -> Code Review**: implementation report submitted (stage 5 begins).
- **Code Review -> Changes Requested**: review verdict = changes-requested (loop to stage 6).
- **Code Review -> Ready for Merge**: review verdict = approve and merge gates green (§7).
- **Ready for Merge -> Done**: human-approved merge completed (stage 8).
- **Blocked / Deferred / Cancelled**: applied at any point; `Deferred` aligns with **DEFERRED** scope ([MVP_SCOPE.md](MVP_SCOPE.md)).

### 2.3 Blocker classification (DECISION D-027)

Blockers are scoped — they do **not** all halt the same thing:

- **RF-004 human architecture approval** gates the **START of M0B as a milestone**. Until the human freeze event (RF-004), no M0B implementation milestone may begin. RF-004 does **not** require that every open question in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) (**Q-001..Q-024**) be resolved.
- **An individual open question blocks ONLY the tickets that depend on its answer** — not M0A completion, not the freeze candidate as a whole, and not unrelated tickets. The dependent ticket records the blocking Q-xxx in its Definition of Ready (§3, item 4).
- **"Accepted Open"** is a permitted status for an open question that is not yet resolved but is safe to proceed around. A question may be marked **Accepted Open** when **ALL FOUR** conditions hold:
  1. an **owner is assigned** for the question;
  2. the **blocking ticket / milestone is identified** (so its scope of impact is explicit);
  3. a **safe interim interface, config, placeholder, or feature flag exists** so dependent work can proceed reversibly; and
  4. **no irreversible schema or contract assumption is made** while the question stays open.

  An Accepted Open question does not block the freeze candidate (RF-004) and does not block tickets other than those that genuinely depend on its answer.

---

## 3. Definition of Ready (DoR)

A ticket may **start** (move to In Progress) **only if ALL** of the following are true. This is a hard gate; Claude Code must refuse to begin work on a ticket that fails any item and flag it back to planning.

1. **Ticket ID exists** — a Jira RF-`<id>` issue exists and is the single unit of work (one active ticket per worktree, §8). Every task has a ticket ID (**DECISION D-016**).
2. **Scope is defined** — what is in and out of this ticket is written down and does not silently expand beyond it (**RISK R-004**; scope boundary owned by [MVP_SCOPE.md](MVP_SCOPE.md)).
3. **Acceptance criteria are defined** — testable, unambiguous criteria that the Definition of Done (§4) can be checked against.
4. **Dependencies are done** — prerequisite tickets are merged (Done) or explicitly stubbed; ordering of dependent work is respected. Sync/dependent-operation ordering rules live in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md). Per the blocker classification (§2.3, **DECISION D-027**), an open question blocks **only** the tickets that depend on its answer; a ticket is not blocked by an unrelated or **Accepted Open** question, and any blocking Q-xxx is recorded here.
5. **Architecture / security impact assessed** — the ticket states whether it touches a frozen architecture document (once the candidate set is frozen after review and approval), a shared package, or an API/RPC contract; whether it affects tenant isolation, RLS, RPC authorization, audit, money, or state machines. If it changes a frozen architecture doc or shared contract, the **architecture-change procedure** (§8) applies **before** code.
6. **Branch + worktree assigned** — the branch name (§4) and the worktree are decided so that no two agents edit the same working tree simultaneously (§8; **DECISION D-016**).

> **SECURITY REQUIREMENT.** Any ticket that touches authentication, authorization, RLS, RPC (`SECURITY DEFINER`), device pairing/sessions, PIN sessions, audit events, or money (**DECISION D-005**..**D-013**) MUST mark its security impact in DoR item 5 and MUST plan the relevant **mandatory isolation/permission tests** before implementation (§4, §7; tests owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)).

---

## 4. Definition of Done (DoD)

A ticket is **Done** (eligible for merge approval) **only if ALL** of the following are true:

1. **Acceptance criteria met** — every criterion from DoR item 3 is satisfied and demonstrable.
2. **Tests written and passing** — unit/widget/integration tests per [TESTING_STRATEGY.md](TESTING_STRATEGY.md), all green in CI (**DECISION D-009**: GitHub Actions).
3. **Mandatory isolation/permission tests present and passing where relevant** — for any tenancy/security-touching change, the canonical isolation set is exercised (owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)): Org A cannot read Org B orders; a `cashier` in Restaurant A cannot modify Restaurant B; a KDS (`kitchen_staff` / device) cannot read financial reports; a revoked device cannot sync new operations; a removed employee cannot create new valid operations; a `cashier` cannot void a paid order without permission; platform-admin access is explicitly audited (**RISK R-003** CRITICAL; **RISK R-007**).
4. **Codex review passed** — review report verdict = approve, with no open **blocker** or **major** findings (§6).
5. **Docs and contracts updated** — if behavior, schema, API/RPC contract, state machine, money rule, or sync rule changed, the owning document is updated in the same ticket: [DOMAIN_MODEL.md](DOMAIN_MODEL.md), [API_CONTRACT.md](API_CONTRACT.md), [STATE_MACHINES.md](STATE_MACHINES.md), [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md), [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md), [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md), or [ARCHITECTURE.md](ARCHITECTURE.md). New frozen choices are recorded in [DECISIONS.md](DECISIONS.md); newly surfaced unknowns are recorded in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).
6. **No silent scope expansion** — the change matches the ticket scope; anything extra is split into its own ticket (**RISK R-004**; **DECISION D-016**).
7. **Human approval** — the human owner approves the merge (§7). No merge without it.

> **DECISION D-018 conformance.** D-018 state enumerations are a **PROPOSED DECISION** (RF-001 §8 explicitly says do not assume the listed values are final; evaluate) — pending ChatGPT + Codex review + Saleh approval; not frozen. Once they are confirmed and frozen, any code touching order, order-item, kitchen-ticket, kitchen-station-item, payment, shift, cash-drawer-session, print-job, device-pairing, or sync-operation status MUST use the exact agreed enumerations and only the transitions defined in [STATE_MACHINES.md](STATE_MACHINES.md). A ticket that introduces a status value not in the agreed set fails DoD.

---

## 5. Branch and commit naming (DECISION D-016, DECISION D-017)

### 5.1 Branch naming

```
<type>/RF-<id>-<slug>
```

- `<type>` is one of: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `infra`.
- `RF-<id>` is the Jira ticket ID (e.g. `RF-001`).
- `<slug>` is a short kebab-case description.

Examples:

```
docs/RF-001-m0a-architecture-freeze
infra/RF-014-melos-monorepo-bootstrap
feat/RF-052-order-state-machine
fix/RF-054-receipt-sequence-reconciliation
test/RF-090-rls-isolation-suite
```

### 5.2 Commit naming (Conventional Commits)

```
<type>(<scope>): <summary> [RF-<id>]
```

- `<type>` from the same set as branch type (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `infra`).
- `<scope>` is a short area, e.g. `pos`, `kds`, `sync`, `auth`, `rls`, `money`, `docs`.
- `<summary>` is imperative, lower-case, no trailing period.
- `[RF-<id>]` ties the commit to its ticket (traceability for **DECISION D-015**).

Examples:

```
docs(workflow): add agent workflow document [RF-001]
feat(sync): add idempotency key on mutating ops [RF-052]
fix(money): store discount in integer minor units [RF-036]
test(rls): org A cannot read org B orders [RF-090]
```

> **SECURITY REQUIREMENT.** Commit messages, branch names, and reports MUST NOT contain secrets, service-role keys, real credentials, or real customer data (§9; **DECISION D-011**).

---

## 6. Implementation report format (produced by Claude Code)

Claude Code produces this report at stage 4–6 of the pipeline and updates it after each fix loop. It accompanies the branch and is the primary input to Codex review.

```markdown
# Implementation Report — RF-<id>

## Ticket
- ID: RF-<id>
- Title: <ticket title>
- Branch: <type>/RF-<id>-<slug>
- Milestone: <M0A|M0B|M1|M2|M3|M4>

## Summary
<2–5 sentences: what was implemented and why, in plain language.>

## Files changed
- path/to/file — <what changed and why>
- ...

## Tests added / changed + results
- <test name / file> — <what it asserts> — PASS/FAIL
- Mandatory isolation/permission tests touched: <list or "n/a — no tenancy/security impact">
- CI status: <green/red + link or run id>

## Contracts touched
- API/RPC: <API_CONTRACT.md sections, or "none">
- Domain/schema: <DOMAIN_MODEL.md entities, or "none">
- State machines: <STATE_MACHINES.md transitions, or "none">
- Money/tax: <MONEY_AND_TAX_SPEC.md rules, or "none">
- Sync: <OFFLINE_SYNC_SPEC.md rules, or "none">

## Security / architecture impact
- Tenant isolation (organization_id) impact: <yes/no + detail>  (DECISION D-001)
- RLS / membership-scope / RPC / DB-constraint layers affected: <which of the four; DECISION D-012>
- Audit events added/changed: <yes/no; DECISION D-013>
- Frozen architecture doc or shared contract changed: <yes/no — if yes, link the §8 architecture-change ticket>
- New DECISIONS.md entries: <D-xxx or none>
- New / affected OPEN_QUESTIONS.md entries: <Q-xxx or none>

## Open risks
- <RISK R-xxx or new risk> — <description + mitigation/status>

## How to verify
- <exact commands / steps a reviewer or human runs to reproduce the passing state>
```

---

## 7. Review report format (produced by Codex)

Codex reviews **read-only by default** (§9) and produces this report at stage 5. Findings are graded by severity; the verdict gates the merge.

```markdown
# Review Report — RF-<id>

## Ticket
- ID: RF-<id>
- Branch reviewed: <type>/RF-<id>-<slug>
- Commit / revision reviewed: <sha or revision>

## Scope reviewed
<What was examined: files, contracts, tests. Note anything intentionally out of scope.>

## Findings by severity
### Blocker  (must fix before merge)
- [file:line] <issue> — <why it blocks>
### Major  (must fix before merge)
- [file:line] <issue>
### Minor  (should fix; may be a follow-up ticket)
- [file:line] <issue>
### Info  (note / suggestion, non-blocking)
- [file:line] <note>

## Isolation / security checks
- Cross-tenant read prevented (Org A vs Org B): <pass/fail/n.a.>  (RISK R-003)
- IDOR / scope checks (cashier cannot cross restaurant; KDS cannot read finance): <pass/fail/n.a.>
- Revoked device / removed employee cannot act (incl. offline window Q-009): <pass/fail/n.a.>  (RISK R-007)
- Sensitive mutation goes through RPC + audit (no service-role key in client): <pass/fail/n.a.>  (DECISION D-011, D-013)
- Money uses integer minor units only — no floating point: <pass/fail/n.a.>  (DECISION D-007)
- State transitions conform to the agreed enumerations (PROPOSED, pending review/approval): <pass/fail/n.a.>  (DECISION D-018)

## Verdict
- [ ] APPROVE  (no open Blocker/Major)
- [ ] CHANGES REQUESTED  (list the blocking findings above)
```

> A verdict of **APPROVE** is required for stage 7; any open **Blocker** or **Major** finding forces **CHANGES REQUESTED** and loops back to Claude Code (stage 6).

---

## 8. Merge gates

A change may be merged **only when ALL** gates are green. The human owner verifies these at stage 7; Claude Code/Codex must not merge without explicit per-merge human authorization (§9).

1. **Ticket is real and Ready/in-review** — RF-`<id>` exists; DoR (§3) was satisfied at start.
2. **Definition of Done met** — every DoD item (§4) is satisfied, including docs/contract updates.
3. **CI green** — all tests pass in GitHub Actions (**DECISION D-009**), including the mandatory isolation/permission suite where relevant (**RISK R-003**).
4. **Codex review = APPROVE** — review report (§7) has no open Blocker/Major findings.
5. **Branch + commit naming valid** — conform to §5.
6. **No forbidden action performed** — see §9; no force push, no `reset --hard`, no database reset, no real-data deletion, no production change, no secret disclosure.
7. **Architecture-change procedure honored** — if a frozen architecture doc or shared contract changed, §8.x below was followed and a [DECISIONS.md](DECISIONS.md) entry exists.
8. **No silent scope expansion** — diff matches ticket scope (**RISK R-004**).
9. **Human approval recorded** — the human owner has explicitly approved this merge (**DECISION D-016**).

---

## 9. Architecture-change procedure (frozen docs and shared contracts)

A change to a **frozen architecture document** (any file in `docs/` listed under "Authoritative document ownership", once the candidate set is frozen after review and approval, e.g. [ARCHITECTURE.md](ARCHITECTURE.md), [DOMAIN_MODEL.md](DOMAIN_MODEL.md), [API_CONTRACT.md](API_CONTRACT.md), [STATE_MACHINES.md](STATE_MACHINES.md), [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md), [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)) **or a shared package / API-RPC contract** is high-impact and follows its own track **before any dependent code is written** (**DECISION D-016**: shared-package and API-contract changes need dedicated tickets).

Procedure:

1. **Dedicated ticket** — open a separate RF-`<id>` for the architecture/contract change; do not fold it into a feature ticket.
2. **ChatGPT + human design** — produce a written design proposal; the human owner approves the direction before implementation.
3. **DECISIONS.md entry before code** — record the new or amended frozen choice as a **DECISION D-xxx** in [DECISIONS.md](DECISIONS.md) (with context/alternatives/consequences). If the change resolves or raises an unknown, update [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) (Q-xxx). No conflicting parallel IDs may be invented (ID ownership: [DECISIONS.md](DECISIONS.md) owns D-xxx, [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) owns Q-xxx).
4. **Codex review** — the architecture/contract change is reviewed independently (§7) like code.
5. **Human approval + merge** — merge gates (§7) apply.
6. **Downstream tickets unblock** — only after the contract is merged may dependent implementation tickets move to Ready.

> **DECISION D-003 / D-018 guard.** No change may regress the tenancy model — that Organization is the tenant and `organization_id` is the primary isolation boundary is an **RF-001 INVARIANT (binding requirement)** (**DECISION D-001**) — or alter a state enumeration (PROPOSED, pending review/approval; once frozen) without an explicit superseding decision in [DECISIONS.md](DECISIONS.md). Silent contradiction of the SHARED CANON is forbidden.

---

## 10. Concurrency, worktrees, and forbidden actions

### 10.1 Concurrency / worktree rules (DECISION D-016)

- **One active ticket per worktree.** Each in-progress ticket has its own branch and its own worktree.
- **Claude Code and Codex must NOT edit the same working tree simultaneously.** Codex reviews **read-only by default**; if Codex needs to run code, it does so in its own checkout/worktree, never the implementer's live tree.
- **Parallel implementation requires separate branches + worktrees.** Two implementation efforts never share a working directory.
- **Every task has a ticket ID.** No off-ticket work.
- **Shared-package and API-contract changes need dedicated tickets** and follow §8.
- Use the worktree tooling to enter/leave isolated trees rather than switching branches in a shared directory.

### 10.2 Forbidden actions (no agent may do these without explicit human approval)

The following are **forbidden** for any AI agent unless the human owner explicitly authorizes the specific action (**DECISION D-016**):

- **No push** to any remote without human approval.
- **No force push** (`git push --force` / `--force-with-lease`) — ever.
- **No `git reset --hard`** (or any history-destroying reset of others' work).
- **No database reset** (no dropping/recreating/truncating real databases or schemas).
- **No deletion of real data** — destructive data operations on real/customer data are prohibited; deletions in the product use **tombstones / soft-delete** (**DECISION D-020**), never hard deletes of tenant data.
- **No production changes** — no deploys, migrations, or configuration changes against production.
- **No secret disclosure** — never print, commit, log, or transmit secrets, service-role keys, real credentials, or real customer PII. **SECURITY REQUIREMENT**: no service-role credentials in clients; no shared restaurant password (**DECISION D-011**).
- **No silent scope expansion** — no work beyond the ticket without a new/updated ticket and human approval (**RISK R-004**).
- **No creating a remote, committing, or pushing during M0A** (§11).

> **DECISION D-013 / D-016.** Platform-admin actions and any sensitive mutation follow the explicitly audited path; the workflow itself is audited through Git history (**DECISION D-015**) and Jira state. Bypassing review or human approval is a process violation, not a shortcut.

---

## 11. M0A constraint (DOCS ONLY)

This document is authored during milestone **M0A** (**DECISION D-019**), whose constraint is **documentation and governance only**. During M0A no agent may create Flutter apps, Dart packages, Supabase folders, SQL migrations, Node projects, package manifests, CI workflows, application/generated code, dashboards, or PM apps; install dependencies; create a remote; commit; or push. Forward-looking process design (this document) is permitted; **execution of the pipeline against code begins in M0B and later** (**DECISION D-019**). The pipeline, gates, and report formats defined here become operative as soon as code work starts.

---

## 12. Cross-references

- Decision log (D-xxx): [DECISIONS.md](DECISIONS.md)
- Open questions (Q-xxx): [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md)
- Scope boundary (in/out, **RISK R-004**): [MVP_SCOPE.md](MVP_SCOPE.md)
- Milestones/timeline/ownership: [PROJECT_PLAN.md](PROJECT_PLAN.md)
- Test strategy (incl. CI): [TESTING_STRATEGY.md](TESTING_STRATEGY.md)
- Security, RLS, isolation/permission tests (**RISK R-003**, **R-007**): [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)
- Entities/fields: [DOMAIN_MODEL.md](DOMAIN_MODEL.md)
- Transitions (PROPOSED state enumerations, approved into the frozen M0A baseline (RF-004); **DECISION D-018**): [STATE_MACHINES.md](STATE_MACHINES.md)
- Money/tax/receipt rules (**DECISION D-007**, **D-008**): [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)
- Sync (**DECISION D-010**, **D-020**, **D-021**, **D-022**): [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)
- API/RPC contracts: [API_CONTRACT.md](API_CONTRACT.md)
- System structure: [ARCHITECTURE.md](ARCHITECTURE.md)
- Backlog: [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) + JIRA_IMPORT.csv
- Concise pointer to this process: `AGENTS.md` (repo root)
