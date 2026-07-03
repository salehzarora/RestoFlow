import { defineConfig, devices } from '@playwright/test';

// RF-112 local browser smoke — Playwright config.
//
// The three RestoFlow web surfaces are started SEPARATELY by the repo-root
// _run_*_real.bat launchers (Flutter web on fixed ports), so there is no
// `webServer` block here — the suite assumes the apps are already running in real
// mode. globalSetup enforces the local-only + no-service-role guards before any
// browser launches.
export default defineConfig({
  testDir: './tests',
  globalSetup: './global-setup.ts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  // Flutter web boot can be slow/variable; a couple of retries absorb boot jitter.
  retries: process.env.CI ? 2 : 1,
  workers: process.env.CI ? 1 : undefined,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    headless: true,
    ignoreHTTPSErrors: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
