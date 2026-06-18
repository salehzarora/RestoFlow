# RestoFlow

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](docs/DECISIONS.md) and [OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md).

## 1. What RestoFlow Is

RestoFlow is a **multi-tenant Restaurant Operating System** — not merely a point-of-sale. It is designed to run the full operational surface of many independent restaurant businesses on a single platform: POS stations for cashiers, Kitchen Display Systems (KDS), owner and manager dashboards, platform administration, plus offline-first operation, synchronization, ESC/POS printing, payments, shifts, cash management, and reporting. The tenant is the **Organization**, which may own one restaurant and one branch (a small café) or many restaurants each with many branches (a restaurant group). The first pilot may run one restaurant and one branch, but no part of the system — schema, API, authorization, local database, or app architecture — assumes only one organization exists.

## 2. Current Status

**M0A — Documentation & Architecture baseline: FROZEN (approved at RF-004).**

The M0A document set was drafted (RF-001, done), independently reviewed by Codex (RF-002), corrected (RF-003, done), and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004 (done)**. The `docs/` set is now the frozen v1 source of truth for technical decisions and contracts; changes require the architecture-change procedure (a new ticket, independent review, and human approval — see [docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md) §8).

There is still **no application code, by design**. RestoFlow follows a documentation-and-architecture-first method ("freeze before code"): the contracts, decisions, state machines, and security model were settled as a complete, reviewed document set — frozen as the M0A architecture baseline at RF-004 — before any Flutter app, Dart package, Supabase migration, or CI workflow is created. The freeze was approved after independent review, required fixes, and Saleh's approval. Application work begins at **M0B** (technical foundation), which has **not** yet started. See [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) for the full milestone structure (**DECISION D-019**: M0A → M0B → M1 → M2 → M3 → M4).

## 3. Repository Contents Now

| Item | Role |
| --- | --- |
| `RestoFlow Project Plan (EN).dc.html` | **LEGACY** planning input — the owner's original v1.0 plan (English). **Not a source of truth.** |
| `RestoFlow Project Plan.dc.html` | **LEGACY** planning input — the owner's original v1.0 plan (Arabic). **Not a source of truth.** |
| `docs/` | The **frozen M0A architecture baseline** (approved at RF-004) — the source of truth for technical decisions and contracts. |
| [CLAUDE.md](CLAUDE.md) | Implementer guidance / shared canon for Claude Code. |
| [AGENTS.md](AGENTS.md) | Agent roles, guardrails, and collaboration rules. |

The two `*.dc.html` v1.0 plan files are **legacy** planning inputs — the owner's original planning artifacts, kept only for provenance. They are **not** sources of truth and must not be edited as canon. Any statement in them that conflicts with the `docs/` set is **superseded** by `docs/` (now frozen at RF-004) — for example **DECISION D-003** supersedes the earlier "Restaurant = Tenant" framing; the tenant is the **Organization**.

## 4. Documentation Map

All documents (the frozen M0A architecture baseline, approved at RF-004) live in `docs/`. Each document owns its topic; other documents reference it rather than redefining it.

### Governance
| Document | Purpose |
| --- | --- |
| [docs/DECISIONS.md](docs/DECISIONS.md) | The decision log (D-001…D-028) — RF-001 invariants plus proposed decisions, each with context, alternatives, consequences (frozen as the M0A baseline at RF-004). |
| [docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md) | The ChatGPT → human → Claude Code → Codex → merge pipeline and guardrails (**DECISION D-016**). |
| [docs/TASK_TRACKER.md](docs/TASK_TRACKER.md) | Concise current-session resume file only — **not** a duplicate backlog. |

### Product
| Document | Purpose |
| --- | --- |
| [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) | Product vision, personas, and surfaces (POS, KDS, dashboards, platform admin). |
| [docs/MVP_SCOPE.md](docs/MVP_SCOPE.md) | What is in and out of MVP scope; tracks **DEFERRED** items. |

### Architecture
| Document | Purpose |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System structure; ties the specs together. |
| [docs/DOMAIN_MODEL.md](docs/DOMAIN_MODEL.md) | Entities, fields, relationships, and the PROPOSED state enumerations in use (approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final). |
| [docs/STATE_MACHINES.md](docs/STATE_MACHINES.md) | Allowed transitions for every state machine (**DECISION D-018** — PROPOSED, approved into the frozen M0A baseline (RF-004)). |

### Specifications
| Document | Purpose |
| --- | --- |
| [docs/SECURITY_AND_THREAT_MODEL.md](docs/SECURITY_AND_THREAT_MODEL.md) | Security model, RLS, threats, and mandatory isolation tests (**DECISION D-011/D-012/D-013**). |
| [docs/OFFLINE_SYNC_SPEC.md](docs/OFFLINE_SYNC_SPEC.md) | Offline-first store, outbox/inbox, idempotency, conflict and tombstone rules (**DECISION D-010/D-020**). |
| [docs/MONEY_AND_TAX_SPEC.md](docs/MONEY_AND_TAX_SPEC.md) | Money, tax, discounts, and receipt numbering (**DECISION D-007/D-008/D-021/D-022**). |
| [docs/PRINTERS_AND_HARDWARE_SPEC.md](docs/PRINTERS_AND_HARDWARE_SPEC.md) | ESC/POS printing and hardware behind a replaceable adapter. |
| [docs/API_CONTRACT.md](docs/API_CONTRACT.md) | RPC / endpoint contracts for sensitive mutations. |
| [docs/TESTING_STRATEGY.md](docs/TESTING_STRATEGY.md) | The test strategy across layers. |

### Planning
| Document | Purpose |
| --- | --- |
| [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) | Milestones (M0A…M4), timeline, and ownership. |
| [docs/IMPLEMENTATION_CHECKLIST.md](docs/IMPLEMENTATION_CHECKLIST.md) | The master human-readable task backlog. |
| [docs/JIRA_IMPORT.csv](docs/JIRA_IMPORT.csv) | The same backlog as a free-Jira-compatible import. |
| [docs/OPERATIONS_AND_RECOVERY.md](docs/OPERATIONS_AND_RECOVERY.md) | Ops, backup, and incident handling. |
| [docs/PILOT_PLAN.md](docs/PILOT_PLAN.md) | The M3 hardware pilot plan. |

### Registers
| Document | Purpose |
| --- | --- |
| [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md) | The open-questions register (Q-001…Q-024) — owner, blocking milestone, status. |

> Cross-cutting **RISKS** (R-001…R-008) are surfaced in the documents where they apply (for example **RISK R-003** RLS cross-tenant leakage in the security spec, **RISK R-002** sync conflicts/duplicates in the offline sync spec).

## 5. Core Principles

These are non-negotiable and apply from the very first migration:

- **Multi-tenant from the first migration.** `organization_id` is the primary tenant-isolation boundary (**DECISION D-001**); the hierarchy is Platform → Organization → Restaurant → Branch → Device/Station (**DECISION D-002**). Nothing assumes a single organization.
- **Per-person identity, no shared accounts.** Every human has an individual identity; roles are membership-scoped, never a permanent global role (**DECISION D-004/D-005**). The six tenant membership role keys are `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant`. Platform administration is **not** a membership role: `platform_admin` is a separate, privileged, audited grant (`platform_admin_grants`) with no `organization_id` (**DECISION D-026**).
- **Offline-first.** The local SQLite/Drift store keeps the POS working with no internet; sync uses an outbox/inbox with idempotency keys (`device_id` + `local_operation_id`). Supabase Realtime is an enhancement only (**DECISION D-010/D-022**).
- **Layered security (defence in depth).** PostgreSQL RLS; membership/role + branch/device scoping; sensitive mutations via SECURITY DEFINER RPC; database constraints as the final boundary (**DECISION D-012** — each layer is an RF-001 requirement; the "four layers" framing is a PROPOSED synthesis pending review). **SECURITY REQUIREMENT** (RF-001 invariant): no service-role credentials in clients; no shared restaurant password.
- **No floating-point money, anywhere.** Money is stored as integer minor units in `_minor` columns (**DECISION D-007**); orders use price snapshots and never recompute from live menu prices (**DECISION D-008**).
- **Arabic, Hebrew, English with full RTL and LTR** (**DECISION D-014**), including localized receipts and tickets.

## 6. How the Team Works

One human owner (Saleh) plus three AI agents: ChatGPT (planning), Claude Code (implementer), Codex (independent reviewer). For roles and guardrails see [AGENTS.md](AGENTS.md); for the full pipeline (plan → human approval → implement → test → review → fix → human approval → merge) see [docs/AGENT_WORKFLOW.md](docs/AGENT_WORKFLOW.md) (**DECISION D-016**).

## 7. Sources of Truth

Per **DECISION D-015**:

- **Jira** (project key `RF`) — official source of truth for **task status**.
- **Git** — official source of truth for **code** and change history.
- **`docs/`** — official source of truth for **technical decisions and contracts**.
- **[docs/TASK_TRACKER.md](docs/TASK_TRACKER.md)** — only a concise current-session resume file, never a duplicate backlog.

The master task list lives in [docs/IMPLEMENTATION_CHECKLIST.md](docs/IMPLEMENTATION_CHECKLIST.md) and [docs/JIRA_IMPORT.csv](docs/JIRA_IMPORT.csv); [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) describes milestones, not individual tickets.
