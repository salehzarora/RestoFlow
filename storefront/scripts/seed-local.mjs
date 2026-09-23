#!/usr/bin/env node
// STOREFRONT-READ-001 - apply scripts/local-storefront-seed.sql to the LOCAL
// Docker Supabase, and nothing else.
//
// The database URL comes from STOREFRONT_LOCAL_DB_URL (default: the CLI stack's
// documented local port) and MUST point at loopback: this script refuses any
// other host, so it can never be aimed at a hosted project. It runs the file
// through the Supabase CLI (`supabase db query --db-url ... -f`), which needs
// the repository's supabase/ directory as its working directory.
//
// CLI quirk (v2.107.0, observed 2026-09-23): the CLI connects WITHOUT TLS only
// when the URL's port is the database port named in supabase/config.toml
// ("Connecting to local database..."); any other loopback port is treated as
// remote, TLS is forced and `sslmode=disable` is ignored ("server refused TLS
// connection"). On a machine whose stack runs on shifted ports (WinNAT), point
// STOREFRONT_LOCAL_DB_URL at the port config.toml names, or shift config.toml
// locally for the run and revert it before committing.
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const STOREFRONT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPO = path.resolve(STOREFRONT, '..');
const SEED = path.join(STOREFRONT, 'scripts', 'local-storefront-seed.sql');

export function localDbUrl(env = process.env) {
  const raw = env.STOREFRONT_LOCAL_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new Error('STOREFRONT_LOCAL_DB_URL is not a URL');
  }
  if (!['postgresql:', 'postgres:'].includes(url.protocol)) throw new Error('STOREFRONT_LOCAL_DB_URL must be a postgres URL');
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) {
    throw new Error(`refusing a non-loopback database host: ${url.hostname} (this seed is LOCAL ONLY)`);
  }
  if (!url.searchParams.has('sslmode')) url.searchParams.set('sslmode', 'disable');
  return url.toString();
}

const SELF_CHECK =
  "select slug, is_published, (public.storefront_menu(slug) ->> 'ok') as anon_ok, (public.storefront_menu(slug) -> 'service' ->> 'state') as state from public.restaurant_storefront_profiles where slug like 'sf-synth-%' order by slug";

function query(dbUrl, args) {
  return execFileSync('supabase', ['db', 'query', '--db-url', dbUrl, ...args], {
    cwd: REPO,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

/** Apply the seed (one DO statement), then return the self-check rows. */
export function seedLocal(env = process.env) {
  const dbUrl = localDbUrl(env);
  query(dbUrl, ['-f', SEED]);
  return query(dbUrl, ['-o', 'json', SELF_CHECK]);
}

if (process.argv[1]?.endsWith('seed-local.mjs')) {
  try {
    const out = seedLocal();
    console.log(out.trim());
    console.log('local storefront seed applied (synthetic tenants sf-synth-a / sf-synth-b / sf-synth-c)');
  } catch (error) {
    const text = String(error.stderr ?? error.message ?? error);
    console.error(text);
    if (/tls error/i.test(text)) {
      console.error(
        'hint: the Supabase CLI skips TLS only for the database port named in supabase/config.toml; ' +
          'use that port in STOREFRONT_LOCAL_DB_URL (or shift config.toml locally and revert it before committing).',
      );
    }
    process.exitCode = 1;
  }
}
