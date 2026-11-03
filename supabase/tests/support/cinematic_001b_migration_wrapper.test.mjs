import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  migrationName, originalCommit, proveWrapperOnly, requireEphemeralCi,
  statements, withoutOuterTransaction,
} from './cinematic_001b_migration_contract.mjs';

test('actual migration removes exactly two outer statement lines', () => {
  const original = execFileSync('git', ['show', `${originalCommit}:supabase/migrations/${migrationName}`], { encoding: 'utf8' });
  const corrected = readFileSync(new URL(`../../migrations/${migrationName}`, import.meta.url), 'utf8');
  const proof = proveWrapperOnly(original, corrected);
  assert.equal(proof.corrected_statements, 11);
  assert.equal(proof.corrected_sha256, '478e950e8e3ac571e439b9dc8a4ae757db7e1e53c234d8f2fb30e9c3343b0462');
});

const wrapped = `-- do not remove this begin;\nbegin;\n\n/* outer /* inner ; */ comment */\ncreate function f() returns void language plpgsql as $body$\nbegin perform ';'; /* commit; */ end;\n$body$;\nselect E'quote\\\';inside', 'doubled'';', "quoted;";\n\ncommit;\n-- keep the tail\n`;

test('scanner respects nested comments, quoted strings and PL/pgSQL bodies', () => {
  assert.equal(statements(wrapped).length, 4);
  const corrected = withoutOuterTransaction(wrapped);
  const proof = proveWrapperOnly(wrapped, corrected, { pinOriginal: false });
  assert.equal(proof.corrected_statements, 2);
  assert.match(corrected, /begin perform ';';/);
  assert.match(corrected, /^-- do not remove this begin;/);
  assert.match(corrected, /-- keep the tail\n$/);
});

test('comment-only or function-body changes fail the byte-preservation proof', () => {
  const corrected = withoutOuterTransaction(wrapped);
  assert.throws(() => proveWrapperOnly(wrapped, corrected.replace('keep the tail', 'changed'), { pinOriginal: false }));
  assert.throws(() => proveWrapperOnly(wrapped, corrected.replace("perform ';'", "perform 'x'"), { pinOriginal: false }));
});

test('unclosed lexical constructs and SQL after final COMMIT fail closed', () => {
  for (const sql of ["select 'broken;", 'select "broken;', '/* broken;', 'do $x$ begin; end;', 'select 1']) {
    assert.throws(() => statements(sql));
  }
  assert.throws(() => withoutOuterTransaction(`${wrapped}select 1;\n`));
  assert.throws(() => withoutOuterTransaction('select 1;\ncommit;\n'));
});

test('local host and unmarked CI are rejected before any command executes', () => {
  assert.throws(() => requireEphemeralCi({}));
  assert.throws(() => requireEphemeralCi({ GITHUB_ACTIONS: 'true', CI: 'true' }));
});

test('ephemeral lane rejects remote endpoint and credential overrides', () => {
  const env = { GITHUB_ACTIONS: 'true', CI: 'true', CINEMATIC_EPHEMERAL: 'BIZBOT-STOREFRONT-CINEMATIC-001B', GITHUB_RUN_ID: '123', RUNNER_TEMP: '/tmp/runner', GITHUB_WORKSPACE: '/tmp/repo' };
  assert.doesNotThrow(() => requireEphemeralCi(env));
  for (const name of ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'SUPABASE_DB_URL', 'SUPABASE_WORKDIR', 'SUPABASE_SERVICES_HOSTNAME', 'DOCKER_HOST', 'DOCKER_CONTEXT', 'PGHOST', 'PGSERVICE', 'PGSERVICEFILE']) {
    assert.throws(() => requireEphemeralCi({ ...env, [name]: 'unexpected' }));
  }
});
