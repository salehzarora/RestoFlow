import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import test from 'node:test';
import {
  migrationName, historicalMigrationName, originalCommit, wrapperOnlyCommit, proveWrapperOnly, proveFinalMigration, requireEphemeralCi,
  statements, withoutOuterTransaction, proveMigrationSequence, predecessorMigrationName, followupMigrations,
} from './cinematic_001b_migration_contract.mjs';

test('historical migration removed exactly two outer statement lines', () => {
  const original = execFileSync('git', ['show', `${originalCommit}:supabase/migrations/${historicalMigrationName}`], { encoding: 'utf8' });
  const corrected = execFileSync('git', ['show', `${wrapperOnlyCommit}:supabase/migrations/${historicalMigrationName}`], { encoding: 'utf8' });
  const proof = proveWrapperOnly(original, corrected);
  assert.equal(proof.corrected_statements, 11);
  assert.equal(proof.corrected_sha256, '478e950e8e3ac571e439b9dc8a4ae757db7e1e53c234d8f2fb30e9c3343b0462');
});

test('final authorized compatibility migration is pinned, atomic and preserves legacy readers', () => {
  const sql = readFileSync(new URL(`../../migrations/${migrationName}`, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
  const proof = proveFinalMigration(sql);
  assert.equal(proof.legacy_readers_unchanged, true);
  assert.throws(() => proveFinalMigration(sql + '\ncommit;\n'));
  assert.throws(() => proveFinalMigration(sql.replace('storefront_menu_v5', 'storefront_menu_v4')));
});

const migrationDirectory = new URL('../../migrations/', import.meta.url);
const currentNames = readdirSync(migrationDirectory).filter(name => /^\d+_.+\.sql$/.test(name)).sort();
// Runtime uses unmodified Linux checkout bytes. Normalize Windows checkout line
// endings only for these cross-platform unit fixtures, never inside the proof.
const followupSources = () => new Map(followupMigrations.map(item => [item.name,
  readFileSync(new URL(item.name, migrationDirectory), 'utf8').replaceAll('\r\n', '\n')]));

test('target prefix ends at the old target and uses its immediate predecessor', () => {
  const plan = proveMigrationSequence(currentNames, followupSources());
  assert.equal(plan.previousVersion, '20261102015942');
  assert.equal(plan.prefixNames.at(-2), predecessorMigrationName);
  assert.equal(plan.prefixNames.at(-1), migrationName);
  assert.deepEqual(plan.prefixNames, currentNames.slice(0, currentNames.indexOf(migrationName) + 1));
  assert.ok(plan.prefixNames.length > 100, 'Every earlier real migration is retained');
  assert.ok(plan.followups.every(item => !plan.prefixNames.includes(item.name)));
  assert.deepEqual(plan.followups.map(item => item.version), ['20261104154000', '20261104155000']);
  assert.ok(plan.followups.every(item => item.no_embedded_transaction && item.statements > 0));
});

test('unknown later or interleaved migration fails the bounded followup proof', () => {
  for (const name of ['20261104160000_unreviewed.sql', '20261104154500_unreviewed.sql']) {
    assert.throws(() => proveMigrationSequence([...currentNames, name].sort(), followupSources()), /Unreviewed followup migration sequence/);
  }
  assert.throws(() => proveMigrationSequence([...currentNames, '20261104130000_new_predecessor.sql'].sort(), followupSources()), /Unreviewed target predecessor/);
});

test('missing target, predecessor or either followup fails closed', () => {
  for (const name of [migrationName, predecessorMigrationName, ...followupMigrations.map(item => item.name)]) {
    assert.throws(() => proveMigrationSequence(currentNames.filter(value => value !== name), followupSources()));
  }
});

test('reordered names and same-version alternate identities cannot change the prefix', () => {
  const reordered = [...currentNames];
  [reordered[reordered.length - 2], reordered[reordered.length - 1]] = [reordered.at(-1), reordered.at(-2)];
  assert.throws(() => proveMigrationSequence(reordered, followupSources()), /Migration sequence must be ordered/);
  assert.throws(() => proveMigrationSequence([...currentNames, '20261104154000_duplicate.sql'].sort(), followupSources()), /Duplicate migration version/);
});

test('missing, changed and CRLF followup bytes all fail exact LF hash pins', () => {
  for (const { name } of followupMigrations) {
    const missing = followupSources(); missing.delete(name);
    assert.throws(() => proveMigrationSequence(currentNames, missing), /Followup migration bytes missing/);
    for (const mutate of [sql => sql + '\n-- changed\n', sql => sql.replaceAll('\n', '\r\n'), sql => sql + '\ncommit;\n']) {
      const changed = followupSources(); changed.set(name, mutate(changed.get(name)));
      assert.throws(() => proveMigrationSequence(currentNames, changed), /Unreviewed followup migration bytes/);
    }
  }
});

test('followup names cannot be swapped while preserving their old content', () => {
  const swapped = followupSources();
  const [first, second] = followupMigrations.map(item => item.name);
  const firstSql = swapped.get(first);
  swapped.set(first, swapped.get(second));
  swapped.set(second, firstSql);
  assert.throws(() => proveMigrationSequence(currentNames, swapped), /Unreviewed followup migration bytes/);
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
