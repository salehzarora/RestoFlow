# RestoFlow browser smoke tests (RF-112)

Local-only [Playwright](https://playwright.dev/) smoke suite that protects the
**visible MVP**. RF-112A is the **foundation**: it stands up the harness and
covers app availability + basic real-mode UI safety. The full onboarding →
order → ticket journey is deferred to RF-112B/RF-112C (see the bottom of this
file).

> **Hard boundaries.** This suite is **local-only** and uses **only the public
> anon/publishable key** — never a service-role/secret key (DECISION D-011,
> RISK R-003). A `globalSetup` guard aborts the run if the environment carries a
> service-role/secret-looking credential, and every navigation is fenced to
> `localhost`. It does **not** reset or seed the database.

## What it covers today (RF-112A)

| Spec | Check |
|---|---|
| `tests/availability.spec.ts` | Dashboard (57026), POS (52096), KDS (49622) are each reachable and boot the Flutter engine without a fatal page error. Renderer-independent — the reliable backbone. |
| `tests/realmode-safety.spec.ts` | Dashboard real mode shows **no demo banner/pill**; first launch is **Arabic/RTL** by default; the **KDS never exposes money** (₪/ILS — SECURITY T-003). |
| `tests/guards.spec.ts` | Unit checks for the local-only fence and the service-role/secret scanner. **No browser** — always runnable. |

### A note on how content is read
The apps are Flutter web builds that paint to a **canvas** (CanvasKit), so there
is no DOM text until Flutter's **accessibility (semantics) tree** is enabled. The
safety specs turn that tree on (`lib/flutter.ts`) and read it. If the tree cannot
be brought up, those specs **fail loudly** ("could not read content") rather than
passing on an empty DOM — the demo/money token lists in `lib/tokens.ts` are then
calibrated against the first live run (RF-112B).

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
npm run smoke:guards         # guard unit checks — no browser, no apps needed
npm run smoke:availability    # just the reachability/boot checks
npm run smoke:safety          # just the real-mode UI-safety checks
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

## Deferred to RF-112B / RF-112C

- The full journey: Dashboard onboarding → menu item → modifiers → table →
  devices → staff/PIN → POS pairing → KDS pairing → POS order → KDS receives
  the ticket.
- Asserting **modifiers / notes / table / order code survive** POS → KDS.
- Stable **semantic anchors / test IDs** in the apps for low-brittleness deep
  navigation (this step adds **no app changes** and leans on the accessibility
  tree + narrow l10n-derived tokens).
- First-live-run **calibration** of the semantics activation and the demo/money
  token lists in `lib/tokens.ts`.
- Optional **CI wiring** (headless, with the stack + apps provisioned).
