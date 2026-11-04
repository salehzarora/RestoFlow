import { defineConfig } from '@playwright/test';
import { resolve } from 'node:path';

// BIZBOT-STOREFRONT-CINEMATIC-001B: genuine local services only. Do not inherit
// the older smoke config's retries or token-bearing traces/screenshots.
export default defineConfig({
  testDir: '.',
  testMatch: 'dashboard.spec.ts',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: true,
  timeout: 900_000,
  expect: { timeout: 25_000 },
  reporter: [['list']],
  outputDir: resolve(process.env.RUNNER_TEMP ?? '.cinematic-private', 'cinematic-private/playwright'),
  use: {
    browserName: 'chromium',
    headless: true,
    actionTimeout: 30_000,
    viewport: { width: 1440, height: 1000 },
    locale: 'ar',
    trace: 'off',
    screenshot: 'off',
    video: 'off',
    serviceWorkers: 'block',
    // Intercepted logical media reads never reach DNS. Everything that does
    // reach Chromium's network stack must resolve to the owned loopback host.
    launchOptions: { args: ['--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1'] },
  },
});
