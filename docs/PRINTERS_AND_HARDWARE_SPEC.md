# PRINTERS_AND_HARDWARE_SPEC

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** FROZEN for M0A (RF-001); frozen as the M0A architecture baseline at RF-004, approved into the frozen M0A baseline (RF-004).
**Owns:** Printing and physical hardware (device classes, connectivity, paper, language/encoding for printing, station routing, print spool, print job lifecycle, retry, duplicate/reprint controls, device health, offline printing, cash drawer, the printing adapter abstraction).
**Does NOT own (reference only):** print job *state transitions* live in [STATE_MACHINES.md](STATE_MACHINES.md); reprint/void/refund money semantics live in [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md); audit/authorization/threats live in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); the offline outbox/inbox/sync engine lives in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md); entities/fields/relationships live in [DOMAIN_MODEL.md](DOMAIN_MODEL.md); receipt/ticket localization rules live in [DECISIONS.md](DECISIONS.md) (D-014) and are detailed in [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) for receipts; the replaceable-adapter contract surfaces in [ARCHITECTURE.md](ARCHITECTURE.md) and [API_CONTRACT.md](API_CONTRACT.md) for any server-assisted pieces.

This document is technology-and-vendor-neutral by intent. Concrete pilot hardware is **OPEN QUESTION Q-006** and is NOT frozen here. ESC/POS is named only as the *first* adapter implementation, never as a coupling baked into the domain.

---

## 1. Scope and principles

RestoFlow is a multi-tenant Restaurant Operating System (**DECISION D-002/D-003**). Printing and hardware MUST work the same way for one branch or for a restaurant group with many branches; nothing in this spec may assume a single restaurant, single branch, or single device. Every hardware entity is tenant-scoped by `organization_id`, with `restaurant_id`, `branch_id`, `device_id`, and `station_id` attached where relevant (**DECISION D-001**, **DECISION D-017**).

Core principles:

1. **Printing is an enhancement to operations, never the source of truth.** An order, payment, kitchen ticket, or shift is valid in the database whether or not a paper artifact ever printed. Print failures degrade convenience, not correctness. This mirrors the offline-first stance in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) and **DECISION D-010**.
2. **Printing sits behind a REPLACEABLE adapter** (Section 12). The domain emits a render-neutral *print document*; an adapter turns it into bytes for a specific device family. ESC/POS is the first adapter (**DECISION D-009**), not the contract.
3. **Print jobs are first-class, durable, idempotent operations** that survive crashes, restarts, and offline windows, using the same idempotency discipline as all mutating ops (**DECISION D-022**: `device_id` + `local_operation_id`).
4. **No floating-point money on any printed artifact.** Amounts are formatted from integer minor units (**DECISION D-007**); the print layer never computes or rounds money, it only renders pre-computed snapshot values (**DECISION D-008**).
5. **Sensitive print actions (reprint of fiscal/receipt artifacts) are audited** with actor, device, and reason (**DECISION D-013**), per [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).

---

## 2. Device classes

RestoFlow distinguishes the following hardware classes. The first two are *compute devices* that run RestoFlow software and carry a **device identity** (**DECISION D-005/D-006**); the rest are *peripherals* attached to (or reachable from) a compute device or the local network.

| Class | Runs RestoFlow? | Identity | Primary role | Notes |
|---|---|---|---|---|
| **POS device** | Yes (Flutter client) | Device identity + device session; humans layer a PIN session (**D-005/D-006**) | Cashier station: order entry, payment, receipt printing, drawer kick | Maps to `devices`/`stations` rows. |
| **KDS device** | Yes (Flutter client) | Device identity + device session | Kitchen Display: shows kitchen tickets, bump/recall | A KDS is an *alternative or complement* to a kitchen printer; both consume the same kitchen ticket data. |
| **Receipt printer** | No | Addressed by a POS device or network | Customer receipt / bill artifact | Typically 80mm or 58mm thermal. Pairs with cash drawer (drawer kick passes through it on serial/USB printers). |
| **Kitchen printer** | No | Addressed via station routing (Section 6) | Prep tickets to a kitchen station | Often impact/dot-matrix for heat tolerance, or thermal. Heat- and grease-tolerant placement. |
| **Cash drawer** | No (electromechanical) | Driven by drawer-kick pulse (Section 11) | Physical cash storage | Usually opened via a kick code routed through the receipt printer; some are USB/relay direct. Bound logically to a `cash_drawer_sessions` row. |

**ASSUMPTION:** a single physical thermal printer model may serve as either a receipt printer or a kitchen printer depending on placement/role; "receipt printer" and "kitchen printer" are *roles*, not necessarily distinct SKUs.

**DEFERRED:** label printers, customer-facing displays (CFD), scales, barcode/QR scanners, and handheld order terminals are out of MVP scope. They are anticipated by the adapter abstraction (Section 12) but not specified here.

Concrete models for all classes are **OPEN QUESTION Q-006** (pilot hardware selection) and **OPEN QUESTION Q-015** (pilot printing connectivity + Arabic/Hebrew encoding strategy).

---

## 3. Connectivity trade-offs (network vs USB vs Bluetooth)

A printer/drawer can be reached by several transports. The choice affects reliability, multi-device sharing, and the offline story. The pilot transport is **OPEN QUESTION Q-015**.

| Transport | Pros | Cons | Multi-device sharing | Offline behavior | RestoFlow fit |
|---|---|---|---|---|---|
| **Network (Ethernet/Wi-Fi, TCP 9100 / IPP)** | Shared by many POS/KDS without cabling; printer reachable by any branch device; clean for KDS-less kitchens; survives a single POS reboot | Depends on LAN/router health; Wi-Fi flakiness causes timeouts; needs IP management (DHCP reservations); a LAN outage can take all printers down at once | Excellent — N devices to 1 printer | Works **fully offline from the internet** as long as the *local* LAN is up; the POS does not need cloud access to print | **Preferred for kitchen printers and shared receipt printers.** Decouples printing from any single POS. |
| **USB** | Simplest, lowest latency, no network config; very reliable point-to-point; drawer kick straightforward | One printer bound to one host device; not shareable; mobile/tablet USB is OS-restricted (OTG, drivers); cable length limits placement | Poor — 1 device to 1 printer | Fully offline; depends only on the attached POS being powered | Good for a dedicated cashier receipt printer + drawer at a fixed POS. |
| **Bluetooth (SPP/BLE)** | No cabling; good for mobile/handheld POS; portable | Pairing fragility; pairing is 1:1 and OS-managed; range/interference; throughput limits for raster images (Arabic/Hebrew rasters, Section 5); battery/sleep disconnects | Poor — effectively 1 device to 1 printer | Fully offline; depends on stable pairing | Niche: portable receipt printing. **Higher risk for raster-heavy multilingual receipts (R-006).** |

**RISK R-001** (ESC/POS hardware variation) and **R-006** (Arabic/Hebrew printing/encoding correctness) both worsen on Bluetooth due to throughput and driver variance.

**ASSUMPTION:** the pilot branch has a reliable local LAN; this favors **network kitchen printers** (resilient to any single POS reboot) and a **USB or network receipt printer + drawer** at each cashier POS. Confirmation is **Q-015**.

**SECURITY REQUIREMENT:** printers and drawers on the branch LAN are unauthenticated commodity devices; they MUST sit on a trusted local network segment and MUST NOT be exposed to the public internet. No tenant data leaves the branch via the printer path. See [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).

---

## 4. Paper width: 58mm vs 80mm

| Aspect | 58mm | 80mm |
|---|---|---|
| Typical print columns | ~32 chars (Font A) | ~42–48 chars (Font A) |
| Use | Compact receipts, portable/mobile | Standard receipts, kitchen tickets, multi-column layouts |
| Pros | Cheaper paper, smaller footprint, portable | Readable in a busy kitchen, fits item+modifiers+qty columns, better for Arabic/Hebrew raster legibility |
| Cons | Cramped layout; multilingual rasters can crowd; long orders waste length | Larger footprint, slightly higher paper cost |

**DECISION D-009 context / ASSUMPTION:** RestoFlow targets **80mm as the default** for both receipts and kitchen tickets because the wider column count is materially better for legible Arabic/Hebrew raster output (**R-006**) and for kitchen tickets that list items + modifiers + station. **58mm MUST remain supported** by the print document + adapter (Section 12) so portable/compact deployments are not excluded.

The print document is authored in **logical columns/abstract layout regions, not fixed pixel widths**, so a single document renders on both widths; the adapter maps logical width to the device's character/dot width. Final paper choice per branch is **OPEN QUESTION Q-006**.

---

## 5. Arabic and Hebrew support (encoding + raster fallback)

Languages are Arabic, Hebrew, English with full RTL/LTR (**DECISION D-014**). Receipts and kitchen tickets MUST be printable in the order/branch language.

Thermal/ESC-POS printers were designed around Latin code pages and have **poor, inconsistent native support for Arabic shaping (contextual joining) and Hebrew**. Two rendering strategies exist:

1. **Native text mode (code-page / built-in font):** fastest, smallest payload. Viable for English and digits. For Arabic this generally FAILS to perform contextual letter joining and RTL bidi correctly; Hebrew support is hardware-dependent. **Not reliable across vendors (R-001, R-006).**
2. **Raster/bitmap mode (render text to an image, send as a bitmap):** the client (Flutter) performs full Unicode shaping + bidi + RTL layout into an image, then sends pixels. **Vendor-independent and correct** for Arabic/Hebrew, at the cost of larger payloads (slower, especially on Bluetooth, Section 3) and dependence on bundled fonts.

**DECISION-aligned policy (cites D-014; raster strategy itself is OPEN QUESTION Q-015):**

- The adapter MUST support a **raster-print fallback** and MUST use it for any line containing Arabic or Hebrew. **RISK R-006** is mitigated by rasterizing on the client where shaping/bidi is fully under our control, plus pilot validation.
- English-only sections MAY use native text mode for speed; mixed-language documents MAY rasterize the whole document for consistency.
- Bundled fonts MUST cover Arabic and Hebrew glyph ranges; the renderer MUST apply correct bidi and RTL alignment. (Glyph/shaping correctness is validated in the pilot per [PILOT_PLAN.md](PILOT_PLAN.md).)
- Money/quantities are rendered from already-formatted strings derived from integer minor units (**D-007**); the print layer never parses or computes amounts.

**OPEN QUESTION Q-015** owns the final encoding/raster strategy and pilot connectivity; this section defines the *direction*, not the frozen vendor specifics.

---

## 6. Printer routing by kitchen station

A branch can have multiple kitchen **stations** (e.g., grill, cold/salad, bar, fryer, pass). Each kitchen ticket / station item is produced for a specific station, and each station maps to a print destination (a kitchen printer) and/or a KDS device.

Routing rules:

- Routing is configured **per branch** as a mapping `station_id -> destination(s)` where a destination is a kitchen printer (by transport address) and/or a KDS device. A station MAY route to both (printer + KDS) for redundancy.
- A single order can fan out to multiple stations: order items are grouped by station, and **one kitchen ticket per station** is produced (consistent with the kitchen ticket / kitchen station item entities in [DOMAIN_MODEL.md](DOMAIN_MODEL.md)).
- Routing is **data-driven and tenant-scoped** (`organization_id`, `restaurant_id`, `branch_id`, `station_id`); no station mapping is hardcoded. A restaurant group's branches each have independent routing.
- If a station has no configured destination, the ticket is still persisted (kitchen ticket state is authoritative; print is best-effort) and the failure is surfaced to staff (Section 9) and recorded; it MUST NOT block order submission.

**ASSUMPTION:** station definitions and the station→destination map are branch-level configuration owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md) (`stations`, plus a routing config entity); this spec only defines the *routing behavior*, not the schema.

---

## 7. Print spool (local print queue)

Each compute device that drives printing maintains a **local, durable print spool** in the offline store (Drift/SQLite, **DECISION D-010**), realized as `print_jobs` rows (**DECISION D-017**).

Properties:

- **Durable:** spooled jobs survive app restart, device reboot, and crash (crash-recovery parity with the sync outbox in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)).
- **Per-destination FIFO ordering:** jobs to the same printer are attempted in creation order so a kitchen ticket and its follow-ups print in sequence; jobs to different destinations proceed independently.
- **Idempotent:** each job carries `device_id` + `local_operation_id` (**DECISION D-022**) so re-enqueue after a crash does not double-print (Section 10).
- **Bounded + observable:** spool depth and failures are visible to staff (Section 9) and contribute to device health (Section 10).
- **Tenant-scoped:** every `print_jobs` row carries `organization_id` and the relevant `restaurant_id`/`branch_id`/`device_id`/`station_id`.

The spool is a *local* concern. Print jobs are NOT part of the cross-device cloud sync payload by default; a paper artifact belongs to the device/printer that produced it. (Cross-device reprint coordination is **DEFERRED**.)

---

## 8. Print job lifecycle, retry, duplicate prevention, reprint + audit

### 8.1 Print job states (reference only)

The print job state machine is **owned by [STATE_MACHINES.md](STATE_MACHINES.md)** (**DECISION D-018**). The PROPOSED state enumeration (approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final) is:

> `created -> queued -> printing -> printed`; plus `failed -> retrying`, `cancelled`, `abandoned` (after max retries). **Terminal:** `printed`, `cancelled`, `abandoned`.

This spec does not redefine transitions; it defines the *operational behavior* that drives them.

### 8.2 Retry

- A job that fails (timeout, paper out, offline printer, transport error) moves `failed -> retrying` and is retried with **exponential backoff + jitter**, consistent with the sync retry discipline in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).
- After a configured **max retry count**, the job becomes `abandoned` (terminal) — the print-layer analog of a poison/dead sync operation — and is surfaced to staff (Section 9). The underlying business record (order/ticket/payment) remains valid and unaffected.
- Retries MUST be idempotent (Section 8.3): a retry re-sends the *same* job identity, never a new one.

### 8.3 Duplicate-print risk and prevention

Duplicate prints (a customer or kitchen seeing two copies, or two physical drawer kicks) are a real hazard from retries, crash recovery, and double taps. Prevention:

- **Idempotency key per job:** `device_id` + `local_operation_id` (**DECISION D-022**). The spool de-duplicates on this key; enqueuing the "same" logical artifact twice collapses to one job.
- **Single-flight per job:** a job in `printing` is not concurrently re-dispatched; only `failed`/`retrying` jobs re-enter the printer.
- **Crash recovery rule:** on restart, a job left in `printing` with unknown outcome is treated as **possibly-printed**. It is NOT silently auto-reprinted; instead it is flagged for staff (Section 9), because the printer cannot reliably confirm completion. Auto-reprint of an unconfirmed job is forbidden to avoid duplicate receipts/drawer kicks.
- **Drawer-kick guard:** a drawer kick is fire-and-forget and physically idempotent within a short window; the system MUST NOT issue repeated kicks on retry (Section 11).

### 8.4 Reprint: reason + audit

A **reprint** is an explicit, intentional re-issue of an artifact (lost receipt, jammed paper, kitchen lost a ticket). It is distinct from an automatic retry.

- A reprint creates a **new** `print_jobs` row with its own idempotency key and a `reprint_of` reference to the original job/artifact. The original is never resurrected.
- **SECURITY REQUIREMENT:** reprinting a **customer receipt / fiscal artifact** is a sensitive action. It requires appropriate permission (role-scoped per [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); e.g. `cashier` may reprint kitchen tickets, while receipt reprints may require `manager`/`restaurant_owner` per branch policy) and MUST capture a **reprint reason**.
- **Reprint emits an append-only audit event** (**DECISION D-013**) with actor, device, organization/restaurant/branch, timestamp, action (`receipt_reprint` / `ticket_reprint`), reason, and a reference to the original artifact. Audit semantics are owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); money/void/refund semantics by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).
- A reprint **changes no money and recomputes nothing**: it renders the *same snapshot values* (**DECISION D-008**); a reprinted receipt is visibly marked as a duplicate/reprint to prevent it being treated as a fresh fiscal document. (Fiscal/legal reprint constraints depend on jurisdiction — **OPEN QUESTION Q-003/Q-004**.)

---

## 9. Printer failure visibility to staff

Silent print failure is unacceptable in a live service. **SECURITY/operational requirement:** the operator must always know whether artifacts actually printed.

- The POS/KDS UI MUST surface a **persistent, non-blocking print status indicator** per destination (e.g., per kitchen printer and the receipt printer) showing healthy / degraded / failed, plus the spool depth.
- A job that reaches `abandoned`, or a crash-recovery `possibly-printed` job (Section 8.3), MUST raise a **clear, actionable alert** to staff with a one-tap **reprint** action (Section 8.4) — which itself respects permission + audit.
- Common physical conditions (paper out, cover open, printer offline/unreachable, drawer-open jam) MUST map to **human-readable messages**, not raw transport errors.
- Failures NEVER block the business operation: an order still submits, a payment still completes, a shift still closes, even if every printer is down. The UI makes the print gap explicit instead.

---

## 10. Device health

RestoFlow tracks health for compute devices and reachable peripherals to support the visibility requirement (Section 9) and pilot operations ([OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md)).

- **Compute devices (POS/KDS):** report a lightweight heartbeat/health signal (app version, last-seen, spool depth, pending sync ops). Health is tenant-scoped and tied to the device identity (`device_id`). Device pairing/lifecycle (`code_issued -> pending -> paired -> active -> suspended -> revoked`, +`code_expired`/`rejected`) is owned by [STATE_MACHINES.md](STATE_MACHINES.md) and authorization by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); this spec only consumes the device's *active* status to decide whether it may drive printers.
- **Peripherals (printers/drawer):** reachability is inferred from print attempts and (for network printers) periodic probes; status feeds the per-destination indicator (Section 9).
- **SECURITY REQUIREMENT:** a **revoked or suspended device MUST NOT print or kick a drawer**, including during an offline window (**RISK R-007**; offline validity window is **OPEN QUESTION Q-009**). Printing capability is gated on the device session being valid, consistent with the four-layer security model (**DECISION D-011/D-012**).

**DEFERRED:** detailed telemetry dashboards, consumable (paper) level prediction, and remote printer management are post-MVP.

---

## 11. Cash drawer kick

- The cash drawer opens via an electrical **kick pulse**. On serial/USB receipt printers the kick is sent as a command *through the printer*; some drawers are USB/relay-driven directly.
- A drawer kick is modeled as a **print-spool job of kind `drawer_kick`** so it inherits durability and idempotency, BUT it is **physically fire-and-forget**: there is no completion confirmation from the hardware.
- **Duplicate-kick prevention:** a `drawer_kick` is NOT auto-retried on uncertain outcome (a second pulse would re-open an already-open drawer pointlessly and confuse cash handling). It carries an idempotency key (**D-022**) and is single-flight (Section 8.3). Repeated user requests within a short window are de-bounced. Concretely (RF-58 / RF-074): the trigger layer creates the job with `max_retries = 0` (one dispatch, then `failed -> abandoned`, never `retrying`), the spool **refuses to reprint** a `drawer_kick` job (Section 8.4 — a reprint would re-open the drawer), and a crash-interrupted kick (`printing -> possiblyPrinted`) is left for manual review and never auto-replayed.
- **Authorization + audit:** opening the drawer outside of a sale (a "no-sale" open) is a sensitive cash-handling action. It requires permission and MUST emit an append-only audit event with actor, device, reason (**DECISION D-013**, per [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)). The drawer is logically bound to the current `cash_drawer_sessions` row (states `opened -> active -> counting -> closed -> reconciled`, owned by [STATE_MACHINES.md](STATE_MACHINES.md)); cash variance/reconciliation money rules are owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).
- **SECURITY REQUIREMENT:** a revoked/suspended device cannot kick the drawer (Section 10, **R-007**).

---

## 12. Offline printing

Printing MUST work with no internet connection (**DECISION D-010**).

- The print spool, render pipeline, and adapters run **entirely on the device / local LAN**. No cloud round-trip is required to produce a receipt, kitchen ticket, or drawer kick.
- Receipt numbering for offline-produced receipts uses the **per-branch monotonic server-assigned sequence with an offline provisional id reconciled on sync** (**DECISION D-021**). The printed provisional/authoritative reconciliation behavior is owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md); the print layer renders whichever id the order currently holds and re-renders on reprint if it later changes.
- Offline jobs follow the normal lifecycle (Section 8); they are not tied to sync state. A device may be fully synced yet unable to reach a printer, or fully offline yet printing perfectly — the two subsystems are independent.
- **SECURITY REQUIREMENT:** offline does NOT relax authorization. A device whose session/permissions were revoked before going offline MUST stop printing/kicking within the offline validity window (**Q-009**, **R-007**).

---

## 13. The replaceable printing adapter (interface, ESC/POS as first implementation)

**DECISION D-009 / architectural requirement:** printing is isolated behind a single, replaceable port so the domain never depends on ESC/POS or any vendor. The structural placement of this port is owned by [ARCHITECTURE.md](ARCHITECTURE.md); here we describe its responsibilities and contract shape (no code in M0A).

### 13.1 Layers

1. **Domain → Print Document (render-neutral):** the domain produces an abstract `PrintDocument` describing *what* to print — logical sections (header, line items with qty/modifiers, totals, footer, kitchen station block), each with language/direction metadata, pre-formatted money strings (from integer minor units, **D-007/D-008**), alignment, and emphasis. It contains **no device codes, no pixel widths, no ESC/POS bytes**.
2. **Print Adapter (port/interface):** consumes a `PrintDocument` + a target `PrinterProfile` (width 58/80mm, native-vs-raster capability, transport) and produces device-ready bytes. The adapter owns Arabic/Hebrew rasterization decisions (Section 5), code-page selection, paper-width column mapping (Section 4), and the cut/kick commands.
3. **Transport (port):** sends bytes over network / USB / Bluetooth (Section 3) and reports best-effort success/failure to the spool.

### 13.2 Adapter responsibilities (interface contract, prose)

A conforming adapter MUST:

- Accept a render-neutral `PrintDocument` and a `PrinterProfile`; never require the caller to know the device family.
- Implement the **raster-print fallback** for Arabic/Hebrew and choose native-vs-raster per line/document (Section 5).
- Map logical layout to **both 58mm and 80mm** column/dot widths (Section 4).
- Emit paper cut and (where applicable) **drawer-kick** commands (Section 11).
- Be **stateless with respect to job identity** — idempotency, retry, and de-duplication are owned by the spool (Sections 7–8), not the adapter.
- Surface structured, human-mappable error categories (paper out, cover open, unreachable) to feed staff visibility (Section 9).

### 13.3 First implementation and roadmap

- **ESC/POS is the first adapter** (**DECISION D-009**), covering common thermal receipt/kitchen printers.
- Because variation across "ESC/POS" devices is real (**RISK R-001**), the `PrinterProfile` abstraction captures per-model quirks (column count, supported code pages, raster command dialect, cut style, kick pin), and the pilot standardizes on **one validated model** to bound variance (**R-001** mitigation; **OPEN QUESTION Q-006/Q-015**).
- **DEFERRED:** additional adapters (Star line-mode, ESC/Label, IPP/driverless, CFD/label) are anticipated by the port but out of MVP scope.

---

## 14. Markers summary (traceability)

- **DECISIONS cited:** D-001, D-002, D-003, D-005, D-006, D-007, D-008, D-009, D-010, D-011, D-012, D-013, D-014, D-017, D-018, D-021, D-022.
- **OPEN QUESTIONS cited:** Q-003, Q-004, Q-006, Q-009, Q-015 (owned by [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md)).
- **RISKS cited:** R-001, R-006, R-007 (owned by [DECISIONS.md](DECISIONS.md)/risk register).
- **SECURITY REQUIREMENTs:** LAN isolation of printers (§3), permission+audit on receipt reprint (§8.4), no printing/kick by revoked devices incl. offline (§10/§11/§12), no auth relaxation offline (§12).
- **DEFERRED:** non-MVP device classes (§2), cross-device reprint (§7), advanced telemetry (§10), additional adapters (§13.3).

**Pilot hardware (all classes, all transports) and the Arabic/Hebrew encoding/raster strategy remain OPEN QUESTION Q-006 and Q-015 and are NOT frozen by this document.**
