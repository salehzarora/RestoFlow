// RF-112A — guard unit checks (no browser).
//
// The local-only fence and the service-role/secret scanner are the security
// spine of the harness, so they are exercised directly with synthetic inputs.
// These specs use no `page` fixture and never launch a browser.

import { test, expect } from '@playwright/test';
import {
  assertLocalOnly,
  assertNoServiceRoleKey,
  findServiceRoleEnv,
} from '../lib/guards';

test.describe('assertLocalOnly', () => {
  for (const url of [
    'http://localhost:57026',
    'http://127.0.0.1:52096',
    'http://[::1]:49622',
    'http://kds.localhost:49622',
  ]) {
    test(`allows local origin ${url}`, () => {
      expect(() => assertLocalOnly(url)).not.toThrow();
    });
  }

  for (const url of [
    'https://app.restoflow.example',
    'http://203.0.113.9',
    'https://dashboard.prod.internal',
  ]) {
    test(`rejects non-local origin ${url}`, () => {
      expect(() => assertLocalOnly(url)).toThrow(/LOCAL-ONLY/);
    });
  }

  test('rejects a malformed URL', () => {
    expect(() => assertLocalOnly('not a url')).toThrow();
  });
});

test.describe('service-role / secret scanner', () => {
  test('a clean anon-key-only env has no offenders', () => {
    const env = {
      RESTOFLOW_SUPABASE_URL: 'http://127.0.0.1:54321',
      RESTOFLOW_SUPABASE_ANON_KEY: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
      PATH: '/usr/bin',
    };
    expect(findServiceRoleEnv(env)).toEqual([]);
    expect(() => assertNoServiceRoleKey(env)).not.toThrow();
  });

  test('flags a value containing service_role', () => {
    const env = { SOME_KEY: 'this-value-has-service_role-in-it' };
    expect(findServiceRoleEnv(env)).toContain('SOME_KEY');
    expect(() => assertNoServiceRoleKey(env)).toThrow(/service-role/);
  });

  test('flags a new-format sb_secret_ key', () => {
    // Built from parts so no literal secret-shaped token sits in source (keeps
    // the repo secret scanner clean); the runtime value still exercises the guard.
    const env = { SUPABASE_KEY: ['sb', 'secret', '0123456789ABCDEFghij'].join('_') };
    expect(findServiceRoleEnv(env)).toContain('SUPABASE_KEY');
  });

  test('flags a legacy service_role JWT by its decoded payload', () => {
    // Built at runtime so no literal JWT appears in source (keeps the repo secret
    // scanner clean); the header is a harmless public constant.
    const header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
    const payload = Buffer.from(
      JSON.stringify({ role: 'service_role', iss: 'supabase' }),
    ).toString('base64url');
    const env = { SB_KEY: [header, payload, 'unsigned'].join('.') };
    expect(findServiceRoleEnv(env)).toContain('SB_KEY');
  });

  test('does NOT flag a non-service-role JWT (e.g. an anon token)', () => {
    const header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
    const payload = Buffer.from(
      JSON.stringify({ role: 'anon', iss: 'supabase' }),
    ).toString('base64url');
    const env = { SB_KEY: [header, payload, 'unsigned'].join('.') };
    expect(findServiceRoleEnv(env)).toEqual([]);
  });

  test('never returns a secret value, only variable names', () => {
    const env = { SECRET_ONE: ['sb', 'secret', '0123456789ABCDEFghij'].join('_') };
    const offenders = findServiceRoleEnv(env);
    expect(offenders).toEqual(['SECRET_ONE']);
    // The value itself is not surfaced anywhere in the result.
    expect(offenders.join(',')).not.toContain('sb_secret_');
  });
});
