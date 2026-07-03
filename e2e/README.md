# RestoFlow browser smoke tests (RF-112)

Local-only [Playwright](https://playwright.dev/) smoke suite that protects the
**visible MVP**. RF-112A is the **foundation** (harness + app availability +
real-mode UI safety); RF-112B adds the **Dashboard setup** flow. The POS/KDS
pairing + order → KDS-ticket journey is deferred to RF-112C (see the bottom).

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
| `tests/guards.spec.ts` (RF-112A) | Unit checks for the local-only fence and the service-role/secret scanner. **No browser** — always runnable. |

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

## Deferred to RF-112C

- The device-side + order journey: **POS pairing** (enter the code), **KDS
  pairing**, **POS staff PIN sign-in**, **POS order creation**, **KDS receives
  the ticket**, and the **KDS money-redaction** check on a live ticket.
- Asserting **modifiers / notes / table / order code survive** POS → KDS.
- Optionally making the RF-112B modifier attach a **hard** assertion (it is
  best-effort today) and adding stable **semantic anchors / test IDs** in the apps
  to cut reliance on Arabic l10n labels (would be an app change, so its own ticket).
- Optional **CI wiring** (headless, with the stack + apps provisioned).
