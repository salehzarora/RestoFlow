import { defineConfig, devices } from '@playwright/test';

// Scoped Playwright config for the storefront shell browser check.
//
// Deliberately separate from e2e/playwright.config.ts: that suite has a
// globalSetup which assumes the three Flutter apps are already running in real
// mode. This one starts nothing but the local static server the spec spawns
// itself, uses an isolated browser context, and never touches a real profile,
// cookie store or hosted service.
//
// Not wired into CI. The plan keeps the browser check a LOCAL gate, so CI never
// downloads a browser; every CI step refers to a script that exists.
export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: {
    headless: true,
    // A fresh, isolated context per test: no owner profile, no stored cookies.
    storageState: undefined,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
    serviceWorkers: 'block', // nothing may mask a network request
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
