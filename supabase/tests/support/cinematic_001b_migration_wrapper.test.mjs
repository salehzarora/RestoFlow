import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  migrationName, historicalMigrationName, originalCommit, wrapperOnlyCommit, proveWrapperOnly, proveFinalMigration, requireEphemeralCi,
  statements, withoutOuterTransaction, finalFingerprint, sha256, predecessorName, predecessorVersion, prefixNamesFingerprint,
  followUpName, followUpVersion, followUpFingerprint, targetFunctions, topLevelTransactionControl, proveFollowUpMigration,
  proveMigrationSequence, targetPrefixSources, followupMigrations, visualReleaseSources, posDutySuccessor,
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

// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-CINEMATIC-PROOF-001: the exact reviewed sequence.
const root = fileURLToPath(new URL('../../../', import.meta.url));
const migrationsDirectory = join(root, 'supabase/migrations');
// A Windows checkout with core.autocrlf writes the LF blobs as CRLF in the
// working tree. Only a file Git reports as `i/lf w/crlf` is converted back;
// every other byte, including a committed CRLF, reaches the contract as is.
const checkoutConverted = new Set(execFileSync('git', ['ls-files', '--eol', '--', 'supabase/migrations'], { cwd: root, encoding: 'utf8' })
  .split('\n').filter((line) => /^i\/lf\s+w\/crlf\s/.test(line)).map((line) => line.slice(line.indexOf('\t') + 1)));
const checkoutBytes = (name) => {
  const bytes = readFileSync(join(migrationsDirectory, name));
  return checkoutConverted.has(`supabase/migrations/${name}`) ? Buffer.from(bytes.toString('latin1').replaceAll('\r\n', '\n'), 'latin1') : bytes;
};
const sources = readdirSync(migrationsDirectory).sort().map((name) => [name, checkoutBytes(name)]);
const bytesOf = (name) => sources.find(([item]) => item === name)[1];
const byName = ([a], [b]) => (a < b ? -1 : a > b ? 1 : 0);
const adding = (...entries) => [...sources, ...entries].sort(byName);
const without = (list, name) => list.filter(([item]) => item !== name);
const replacing = (name, bytes) => sources.map(([item, value]) => [item, item === name ? bytes : value]);
const sql = (text) => Buffer.from(text);
const crlf = (bytes) => Buffer.from(bytes.toString('latin1').replaceAll('\n', '\r\n'), 'latin1');
// Strict assert appends its diff to a custom message; the runner's receipt keeps
// only the first line, so the refusal is identified by that line.
const failsWith = (message) => (error) => error.message.split('\n')[0] === message;
const refuses = (list, message) => assert.throws(() => proveMigrationSequence(list), failsWith(message));

test('the sequence pins #379, payment 001D, product helpers, scene and background clarity', () => {
  assert.deepEqual(proveMigrationSequence(sources).summary, {
    migrations: 189, before_target: 183, predecessor: predecessorName, target: migrationName, later_than_target: [followUpName, ...followupMigrations.map(item => item.name), posDutySuccessor.name],
    prefix_names_sha256: prefixNamesFingerprint, follow_up_sha256: followUpFingerprint, follow_up_statements: 125,
    follow_up_no_embedded_transaction: true,
    visual_followups: followupMigrations.map(pin => ({ ...pin, version: pin.name.slice(0, 14), statements: statements(bytesOf(pin.name).toString('utf8')).length, no_embedded_transaction: true })),
    excluded_successor: posDutySuccessor,
  });
});

test('the target prefix ends at #379 and excludes 001D, which is applied only as the reviewed follow-up', () => {
  const { target_prefix: prefix } = proveMigrationSequence(sources);
  assert.equal(prefix.length, 184);
  assert.deepEqual(prefix.slice(-2), [predecessorName, migrationName]);
  assert.ok(!prefix.includes(followUpName));
  assert.deepEqual(sources.map(([name]) => name), [...prefix, followUpName, ...followupMigrations.map(item => item.name), posDutySuccessor.name]);
  const broken = sql('select 1;\n');
  const plan = targetPrefixSources(sources, broken);
  assert.deepEqual(plan.map(([name]) => name), prefix);
  assert.ok(plan.at(-1)[1] === broken, 'The plan must carry the given target bytes');
  assert.ok(plan.slice(0, -1).every(([name, bytes]) => bytes === bytesOf(name)));
  assert.equal(sha256(targetPrefixSources(sources, bytesOf(migrationName)).at(-1)[1]), finalFingerprint);
  assert.throws(() => targetPrefixSources(without(sources, followUpName), broken), failsWith('Missing the reviewed 001D follow-up migration'));
  assert.throws(() => targetPrefixSources(sources, 'select 1;\n'), failsWith('Migration sources must be raw bytes'));
});

test('unknown later and interleaved migrations fail', () => {
  const extra = sql('select 1;\n');
  refuses([...without(sources, followUpName), ['20261104150000_unknown_later.sql', extra]].sort(byName), 'Missing the reviewed 001D follow-up migration');
  refuses(adding(['20261104140000_interleaved.sql', extra]), 'Interleaved migration between the #379 target and the 001D follow-up');
  refuses(adding(['20261103000000_interleaved.sql', extra]), 'The #379 target must directly follow its exact predecessor');
  refuses(adding(['20261020000000_interleaved.sql', extra]), 'Unreviewed migration sequence before the #379 target');
  refuses(adding(['20250101000000_older_than_every_migration.sql', extra]), 'Unreviewed migration sequence before the #379 target');
  const [firstName, firstBytes] = sources[0];
  refuses(without(sources, firstName), 'Unreviewed migration sequence before the #379 target');
  refuses([[`${firstName.slice(0, 15)}renamed.sql`, firstBytes], ...sources.slice(1)], 'Unreviewed migration sequence before the #379 target');
});

test('a missing target, predecessor or 001D follow-up fails', () => {
  refuses(without(sources, migrationName), 'Missing the exact #379 target migration');
  refuses(without(sources, predecessorName), 'The #379 target must directly follow its exact predecessor');
  refuses(without(sources, followUpName), 'Missing the reviewed 001D follow-up migration');
});

test('reordered and duplicate versions fail', () => {
  const swapped = [...sources];
  [swapped[183], swapped[184]] = [swapped[184], swapped[183]];
  refuses(swapped, 'Migration versions must be strictly ascending');
  refuses([...sources].reverse(), 'Migration versions must be strictly ascending');
  refuses(adding([`${followUpVersion}_duplicate_version.sql`, sql('select 1;\n')]), 'Duplicate migration version');
  refuses(adding([`${predecessorVersion}_duplicate_version.sql`, sql('select 1;\n')]), 'Duplicate migration version');
  // 001D moved before the #379 target by version, with its name suffix and bytes.
  refuses([...without(sources, followUpName), ['20261104120000_bizbot_zcredit_001d_server_ledger.sql', bytesOf(followUpName)]].sort(byName),
    'The #379 target must directly follow its exact predecessor');
});

test('changed, CRLF-converted or renamed 001D bytes fail', () => {
  const original = bytesOf(followUpName);
  refuses(replacing(followUpName, Buffer.concat([original, sql('-- changed\n')])), 'Unreviewed 001D follow-up bytes');
  refuses(replacing(followUpName, crlf(original)), 'Unreviewed 001D follow-up bytes');
  refuses(replacing(followUpName, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), original])), 'Unreviewed 001D follow-up bytes');
  // Changes at the end of the file only: no end-of-file normalization may precede the hash.
  assert.equal(original.at(-1), 0x0a);
  for (const tail of ['\n', '\r\n', '   \n', '\n\n']) {
    refuses(replacing(followUpName, Buffer.concat([original, sql(tail)])), 'Unreviewed 001D follow-up bytes');
  }
  refuses(replacing(followUpName, original.subarray(0, -1)), 'Unreviewed 001D follow-up bytes');
  refuses(replacing(followUpName, Buffer.concat([original.subarray(0, -1), sql('\r\n')])), 'Unreviewed 001D follow-up bytes');
  // Renamed with the same contents: another name, or another version.
  refuses([...without(sources, followUpName), ['20261104141959_bizbot_zcredit_001d_renamed.sql', original]].sort(byName), 'Missing the reviewed 001D follow-up migration');
  refuses([...without(sources, followUpName), ['20261104142000_bizbot_zcredit_001d_server_ledger.sql', original]].sort(byName), 'Missing the reviewed 001D follow-up migration');
  // The reviewed bytes copied under another name.
  refuses(replacing(sources[0][0], original), 'The reviewed 001D bytes may appear only under their pinned name');
  refuses(replacing(sources[0][0], bytesOf(migrationName)), 'The reviewed #379 target bytes may appear only under its pinned name');
  // The #379 target stays pinned by #379's own final-migration proof.
  refuses(replacing(migrationName, crlf(bytesOf(migrationName))), 'Unreviewed final migration bytes');
});

test('top-level transaction control in the 001D follow-up fails; dollar-quoted PL/pgSQL does not', () => {
  const original = bytesOf(followUpName);
  const message = 'Unexpected top-level transaction control in the 001D follow-up';
  for (const control of ['begin;', 'BEGIN WORK;', 'begin isolation level serializable;', 'start transaction;', 'commit;',
    "commit prepared 'x';", 'end;', 'rollback;', 'rollback to savepoint s;', 'abort;', 'savepoint s;', 'release savepoint s;',
    "prepare transaction 'x';", 'start\ntransaction;', 'START\tTRANSACTION;', 'start  transaction;', "prepare\ntransaction 'x';"]) {
    refuses(replacing(followUpName, Buffer.concat([original, sql(`${control}\n`)])), message);
    refuses(replacing(followUpName, Buffer.concat([sql(`-- leading\n${control}\n`), original])), message);
  }
  // Between two top-level statements as well. Offsets are positions in the decoded text (the 001D holds non-ASCII
  // characters), so the control is inserted there and the text re-encoded.
  const text = original.toString('utf8');
  const all = statements(text);
  for (const index of [1, Math.floor(all.length / 2), all.length - 2]) {
    for (const control of ['commit;', 'begin;', 'start\ntransaction;', "prepare  transaction 'x';"]) {
      const at = all[index].end;
      refuses(replacing(followUpName, Buffer.from(`${text.slice(0, at)}\n${control}${text.slice(at)}`)), message);
    }
  }
  assert.deepEqual(topLevelTransactionControl(original.toString('utf8')), []);
  assert.deepEqual(topLevelTransactionControl(
    "do $$ begin perform 1; end $$;\ncreate function f() returns void language plpgsql as $f$ begin return; end; $f$;\n" +
    "prepare q as select 1;\nselect 'commit;';\nbegin_audit();\nending();\n"), []);
  assert.throws(() => proveFollowUpMigration(original.toString('utf8')), failsWith('Migration sources must be raw bytes'));
});

test('a second later migration fails, including any future follow-up not yet pinned', () => {
  refuses(adding(['20261104150000_second_later.sql', sql('select 1;\n')]), 'Unexpected migration sequence after the #379 target');
  const future = ['20261106122400_future_follow_up.sql', '20261106122500_future_follow_up.sql'];
  assert.ok(future.every(name => name.slice(0, 14) > followupMigrations.at(-1).name.slice(0, 14)));
  refuses(adding([future[0], sql('select 1;\n')], [future[1], sql('select 2;\n')]),
    'Unexpected migration sequence after the #379 target');
});

test('non-conforming migration names and sources fail', () => {
  for (const name of ['2026110415001_short_version.sql', '202611041500001_long_version.sql', '20261104150000_Upper.sql',
    '20261104150000-dash.sql', '20261104150000_x.SQL', '20261104150000_x.sql.bak', '20261104150000_.sql', 'README.md']) {
    refuses(adding([name, sql('select 1;\n')]), 'Migration file names must be a 14-digit version, a lower-case name and .sql');
  }
  refuses([], 'Expected the migration directory listing');
  refuses(replacing(followUpName, bytesOf(followUpName).toString('utf8')), 'Migration sources must be raw bytes');
  refuses(replacing(sources[0][0], bytesOf(sources[0][0]).toString('latin1')), 'Migration sources must be raw bytes');
});

test('the exact #379 and 001D hashes and the reviewed sequence are pinned', () => {
  assert.equal(migrationName, '20261104131256_bizbot_storefront_cinematic_001b_appearance.sql');
  assert.equal(finalFingerprint, 'a276aef4fdd30b35272939e51d649bff3dfeb70b6c806ecb7c2edee94ceb263b');
  assert.equal(followUpName, '20261104141959_bizbot_zcredit_001d_server_ledger.sql');
  assert.equal(followUpFingerprint, '468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e');
  assert.equal(predecessorName, '20261102015942_bizbot_storefront_seo_discovery_001.sql');
  assert.equal(prefixNamesFingerprint, '6ee60a7fc86607ebbcd69492f551f673622336c4476823ee8a2c014106f15643');
  assert.equal(predecessorVersion, predecessorName.slice(0, 14));
  assert.equal(followUpVersion, followUpName.slice(0, 14));
  assert.equal(sha256(bytesOf(migrationName)), finalFingerprint);
  assert.equal(sha256(bytesOf(followUpName)), followUpFingerprint);
  const created = statements(bytesOf(migrationName).toString('utf8'))
    .map((item) => item.text.match(/^create\s+(?:or\s+replace\s+)?function\s+([a-z_]+\.[a-z0-9_]+)\s*\(/i)?.[1])
    .filter(Boolean);
  assert.deepEqual(created.sort(), [...targetFunctions].sort());
});

test('all visual migrations fail closed on missing, swapped, changed, CRLF or copied bytes', () => {
  for (const pin of followupMigrations) {
    refuses(without(sources, pin.name), 'Unexpected migration sequence after the #379 target');
    const original = bytesOf(pin.name);
    for (const changed of [Buffer.concat([original, sql('-- changed\n')]), crlf(original), original.subarray(0, -1)]) {
      refuses(replacing(pin.name, changed), 'Unreviewed visual follow-up bytes');
    }
    refuses(replacing(pin.name, Buffer.concat([original, sql('commit;\n')])), 'Unexpected transaction control in a visual follow-up');
    refuses(replacing(sources[0][0], original), 'Reviewed visual bytes may appear only under their pinned name');
    refuses(adding([pin.name.slice(0, 15) + 'duplicate.sql', sql('select 1;\n')]), 'Duplicate migration version');
  }
  const [product, scene] = followupMigrations.map(pin => pin.name);
  refuses(sources.map(([name, bytes]) => [name, name === product ? bytesOf(scene) : name === scene ? bytesOf(product) : bytes]),
    'Unreviewed visual follow-up bytes');
  const between = '20261105025500_between_product_and_scene.sql';
  assert.ok(product.slice(0, 14) < between.slice(0, 14) && between.slice(0, 14) < scene.slice(0, 14));
  refuses(adding([between, sql('select 1;\n')]),
    'Unexpected migration sequence after the #379 target');
});

test('production-shaped proof omits pending payment and the later POS release after exact source validation', () => {
  const plan = visualReleaseSources(sources);
  assert.deepEqual(plan.map(([name]) => name), [
    ...proveMigrationSequence(sources).target_prefix, ...followupMigrations.map(item => item.name),
  ]);
  assert.ok(plan.every(([name, bytes]) => bytes === bytesOf(name)), 'Exact bytes are retained');
  assert.ok(!plan.some(([name]) => name === followUpName));
  for (const pin of [followUpName, ...followupMigrations.map(item => item.name), posDutySuccessor.name]) {
    assert.throws(() => visualReleaseSources(without(sources, pin)));
    assert.throws(() => visualReleaseSources(replacing(pin, Buffer.concat([bytesOf(pin), sql('-- changed\n')]))));
  }
  assert.throws(() => visualReleaseSources(adding(['20261104160000_unreviewed.sql', sql('select 1;\n')])));
});

test('both historical plans exclude exactly the pinned POS successor and refuse a changed, copied or later file', () => {
  const { name, sha256: digest } = posDutySuccessor;
  assert.equal(name, '20261106180840_bizbot_pos_long_shift_alerts_001.sql');
  const original = bytesOf(name);
  assert.equal(sha256(original), digest);
  const historical = proveMigrationSequence(sources).historical_names;
  assert.equal(historical.length, 188);
  assert.deepEqual([...historical, name], sources.map(([entry]) => entry));
  assert.deepEqual(visualReleaseSources(sources).map(([entry]) => entry), historical.filter(entry => entry !== followUpName));
  refuses(without(sources, name), 'Unexpected migration sequence after the #379 target');
  refuses(replacing(name, crlf(original)), 'Unreviewed POS duty successor bytes');
  refuses(replacing(name, Buffer.concat([original, sql('-- changed\n')])), 'Unreviewed POS duty successor bytes');
  refuses(replacing(sources[0][0], original), 'Reviewed POS duty bytes may appear only under their pinned name');
  refuses(adding(['20261106190000_unknown.sql', original]), 'Unexpected migration sequence after the #379 target');
});
