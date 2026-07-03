import { defineConfig, devices } from '@playwright/test';

// RF-112 local browser smoke — Playwright config.
//
// The three RestoFlow web surfaces are started SEPARATELY by the repo-root
// _run_*_real.bat launchers (Flutter web on fixed ports), so there is no
// `webServer` block here — the suite assumes the apps are already running in real
// mode. globalSetup enforces the local-only + no-service-role guards before any
// browser launches.
//
// SERIAL on purpose (workers=1, no fullyParallel): locally the apps are `flutter
// run` DEBUG builds that boot via DDC (~1000 module scripts). Booting more than
// one at a time starves the CPU and makes the heaviest surfaces (Dashboard/KDS)
// miss their boot window. Running one page at a time is far more reliable than it
// is slow for a 3-app smoke. The per-test timeout sits comfortably ABOVE the boot
// wait (lib/flutter.ts bootTimeoutMs, default 90s) so a boot failure surfaces as a
// diagnostic while the page is still open, not as a "page closed" test timeout.
export default defineConfig({
  testDir: './tests',
  globalSetup: './global-setup.ts',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  timeout: 180_000,
  expect: { timeout: 20_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    headless: true,
    ignoreHTTPSErrors: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
    // The dashboard setup reads a one-time pairing code via the Copy button +
    // clipboard (the code paints to canvas and is not in the DOM). Local-only.
    permissions: ['clipboard-read', 'clipboard-write'],
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
