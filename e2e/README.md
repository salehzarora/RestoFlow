# RestoFlow browser smoke tests (RF-112)

Local-only [Playwright](https://playwright.dev/) smoke suite that protects the
**visible MVP**. RF-112A is the **foundation** (harness + app availability +
real-mode UI safety); RF-112B adds the **Dashboard setup** flow; RF-112C adds the
**POS → KDS** real order flow. Together they cover the end-to-end local MVP path.

> **Hard boundaries.** This suite is **local-only** and uses **only the public
> anon/publishable key** — never a service-role/secret key (DECISION D-011,
> RISK R-003). A `globalSetup` guard aborts the run if the environment carries a
> service-role/secret-looking credential, and every navigation is fenced to
> `localhost`. It does **not** reset or seed the database.

## What it covers today

| Spec | Check |
|---|---|
| `tests/availability.spec.ts` (RF-112A) | Dashboard (57026), POS (52096), KDS (49622) are each reachable and boot the Flutter engine without a fatal page error. Renderer-independent — the reliable backbone. |
| `tests/realmode-safety.spec.ts` (RF-112A) | Dashboard real mode shows **no demo banner/pill**; first launch is **Arabic/RTL** by default; the **KDS never exposes money** (₪/ILS — SECURITY T-003). |
| `tests/dashboard-setup.spec.ts` (RF-112B) | Signs up a **unique** owner, onboards a restaurant/branch, and (in real mode) creates a **menu category + item (ILS price) + modifier template**, a **table**, a **POS + KDS device each with a one-time pairing code**, and a **cashier + kitchen-staff member each with a PIN** — then asserts the Overview **Setup Center** shows the matching progress. |
| `tests/pos-kds-flow.spec.ts` (RF-112C) | Runs the RF-112B setup, **captures the two real pairing codes**, then in **isolated contexts** pairs the **POS** + signs in the cashier PIN + places a **dine-in order** (table + item + required modifier + item note) and pairs the **KDS** + signs in the kitchen PIN, and asserts the **same `#XXXXXX` order code, table, item, modifier and note** appear on the KDS ticket — and that the **KDS stays money-free** on a live ticket (T-003). |
| `tests/guards.spec.ts` (RF-112A) | Unit checks for the local-only fence and the service-role/secret scanner. **No browser** — always runnable. |

### The POS → KDS flow smoke (RF-112C)
`pos-kds-flow.spec.ts` is the end-to-end path. It reuses the shared `lib/setup_flow.ts`
to create a fresh branch and **read each device's one-time enrollment code** from
the Dashboard issue-code dialog — the code paints to canvas (not in the DOM), so it
is captured by hooking `navigator.clipboard.writeText` and tapping **Copy** (the
run grants clipboard permission; local-only). It then drives POS and KDS in **three
separate browser contexts** (Dashboard / POS / KDS) so a prior manual session never
interferes and each device starts **unpaired**. Devices are created **one at a time**
(each code captured while its device is the only one present) so the POS code is a
POS code and the KDS code is a KDS code (a mismatch is rejected `wrong_type`). No
Flutter app changes. The single KDS forward step (Acknowledge) is best-effort. Run
just this spec with `npx playwright test pos-kds-flow`.

### The Dashboard setup smoke (RF-112B)
`dashboard-setup.spec.ts` drives the **real** Dashboard through the owner setup
that prepares a branch for POS/KDS. It creates **unique, timestamped** data every
run (no db reset, no deletion of existing data) and starts from a **fresh
Playwright context** (isolated storage → always signed out). It targets elements
by **ARIA role + accessible name** from the Arabic (default) l10n via `lib/dashboard.ts`
— **no Flutter app changes**. Flutter fills need real keystrokes (focus → clear →
type), tiles/options are matched by their accessible name, and the inline item
editor / modal dialogs are closed so the side-nav stays reachable. Attaching the
modifier template is **best-effort** (it re-opens the item editor); if it can't, the
run logs `modifier: SKIPPED` and continues — the rest still asserts. Run just this
spec with `npx playwright test dashboard-setup`.

### A note on how content is read
The apps are Flutter web builds that paint to a **canvas** (CanvasKit), so there
is no DOM text until Flutter's **accessibility (semantics) tree** is enabled. The
safety specs turn that tree on (`lib/flutter.ts`) and read it. If the tree cannot
be brought up, those specs **fail loudly** ("could not read content") rather than
passing on an empty DOM — the demo/money token lists in `lib/tokens.ts` are then
calibrated against the first live run (RF-112B).

### Why the suite runs serially (and can be slow on first boot)
Locally the apps run under `flutter run` in **debug** mode, which boots via the
Dart Development Compiler (DDC): the page loads ~1000 module scripts before the
Flutter view attaches. Booting several apps at once starves the CPU and the
heaviest surfaces (Dashboard/KDS) miss their boot window, so the config runs
**one page at a time** (`workers: 1`). The per-test timeout (180s) sits above the
boot wait (default 90s). If your machine is slow or the first compile is heavy,
raise the boot budget:

```
RF_E2E_BOOT_TIMEOUT_MS=150000 npm run smoke
```

A boot failure prints diagnostics (final URL, HTTP status, title, a safe body
snippet, console + page errors) so a still-loading build or a config/help page is
obvious rather than a bare timeout.

## Prerequisites

1. **Node** ≥ 18 (repo is validated on Node 22).
2. The **local Supabase stack** running (`supabase start`) so the apps come up in
   real mode rather than the honest "unconfigured" screen.
3. The **three apps running in real mode** on their fixed ports — from the repo
   root, in three separate terminals:
   ```
   _run_dashboard_real.bat   # http://localhost:57026
   _run_pos_real.bat         # http://localhost:52096
   _run_kds_real.bat         # http://localhost:49622
   ```

## Install (first time)

```
cd e2e
npm install
npm run install:browsers    # downloads the Chromium Playwright build
```

## Run the smoke suite

```
cd e2e
npm run smoke               # all specs (apps must be running)
```

Useful subsets:

```
npm run smoke:guards          # guard unit checks — no browser, no apps needed
npm run smoke:availability    # just the reachability/boot checks
npm run smoke:safety          # just the real-mode UI-safety checks
npx playwright test dashboard-setup   # just the RF-112B setup flow (~1–2 min)
npx playwright test pos-kds-flow      # just the RF-112C POS→KDS flow (~2 min)
npm run smoke:headed          # watch it drive a visible browser
npm run list                  # enumerate tests without running them
npm run report                # open the last HTML report
```

Override a port for a non-default run (still local-only):

```
RF_E2E_DASHBOARD_URL=http://localhost:5000 npm run smoke:availability
```

## If the apps are not running

The suite does **not** fake success. `availability` fails with
`No HTTP response … — is <app> running?`. Start the three launchers above, make
sure `supabase start` is up, then re-run `npm run smoke`.

## Out of scope after RF-112C

RF-112 (A + B + C) now covers the end-to-end local MVP path. Remaining ideas, each
its own future ticket:

- **KDS workflow transitions** beyond the single best-effort Acknowledge (Start →
  Mark ready → Bump) and asserting the re-bucketing across columns.
- **Payment / receipt** on POS (cash payment sheet, change, the "Paid" pill) and
  **honest print** assertions (prepared-not-printed — no physical printer here).
- Promoting the **modifier** attach + **item note** from best-effort to hard
  assertions, and adding stable **semantic anchors / test IDs** in the apps to cut
  reliance on Arabic l10n labels (an app change → its own ticket).
- **CI wiring** (headless, with the Supabase stack + the three apps provisioned and
  booted before the run).
- Multi-item carts, takeaway orders, table-status changes, and offline/outbox retry
  paths.
