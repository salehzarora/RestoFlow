import { defineConfig, devices } from '@playwright/test';

// Phase F cross-engine smoke. The Chromium matrix stays in playwright.config.ts;
// this config exists only so the six smoke cases (G02, G04, G17, G22, G30 and
// the shortened X01) run on Firefox and on Playwright's WebKit, which is NOT
// Safari and is recorded as such. Same isolation as the main config: no
// profile, no cookies, no service worker, the spec spawns its own loopback
// server. Not wired into CI.
export default defineConfig({
  testDir: '.',
  testMatch: /storefront-ui-001f-cross\.spec\.ts/,
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 15_000 },
  reporter: [['list']],
  use: {
    headless: true,
    storageState: undefined,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
    serviceWorkers: 'block',
  },
  projects: [
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
});
