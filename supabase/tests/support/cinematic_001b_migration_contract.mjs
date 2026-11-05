// BIZBOT-STOREFRONT-CINEMATIC-001B: bounded proof for this one migration.
// This is a PostgreSQL lexical statement scanner, not a SQL reformatter.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

export const historicalMigrationName = '20261102140930_bizbot_storefront_cinematic_001b_appearance.sql';
export const migrationName = '20261104131256_bizbot_storefront_cinematic_001b_appearance.sql';
export const migrationVersion = '20261104131256';
export const wrapperOnlyCommit = '84d73363c218735648ab1b778337fb6ffdebfcd0';
export const finalFingerprint = 'a276aef4fdd30b35272939e51d649bff3dfeb70b6c806ecb7c2edee94ceb263b';
export const originalCommit = 'e71ab13dc258b5bc036b29a054e3744cb824d63e';
export const originalFingerprint = 'b68c7d6a74dd91179042e65f038e2b1a85c58cc6efbc0e8713871f6d34669038';
export const sha256 = (value) => createHash('sha256').update(value).digest('hex');

// PostgreSQL's semicolons inside strings, quoted identifiers, nested comments
// and dollar-quoted bodies do not end top-level statements. In particular,
// PL/pgSQL BEGIN/END inside a dollar quote is never a transaction wrapper.
export function statements(sql) {
  const result = [];
  let index = 0, first = null;
  while (index < sql.length) {
    const char = sql[index];
    if (/\s/.test(char)) { index++; continue; }
    if (sql.startsWith('--', index)) {
      const end = sql.indexOf('\n', index + 2);
      index = end < 0 ? sql.length : end + 1;
      continue;
    }
    if (sql.startsWith('/*', index)) {
      index += 2;
      let depth = 1;
      while (index < sql.length && depth) {
        if (sql.startsWith('/*', index)) { depth++; index += 2; }
        else if (sql.startsWith('*/', index)) { depth--; index += 2; }
        else index++;
      }
      assert.equal(depth, 0, 'Unterminated SQL block comment');
      continue;
    }
    first ??= index;
    if (char === "'" || char === '"') {
      const quote = char;
      const escapedString = quote === "'" && index > 0 && /[eE]/.test(sql[index - 1]) &&
        (index === 1 || !/[\w$]/.test(sql[index - 2]));
      index++;
      let closed = false;
      while (index < sql.length) {
        if (escapedString && sql[index] === '\\') { index += 2; continue; }
        if (sql[index] === quote) {
          if (sql[index + 1] === quote) { index += 2; continue; }
          index++; closed = true; break;
        }
        index++;
      }
      assert.ok(closed, 'Unterminated SQL quote');
      continue;
    }
    if (char === '$' && (index === 0 || !/[\w$]/.test(sql[index - 1]))) {
      const tag = sql.slice(index).match(/^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$/)?.[0];
      if (tag) {
        const end = sql.indexOf(tag, index + tag.length);
        assert.ok(end >= 0, 'Unterminated SQL dollar quote');
        index = end + tag.length;
        continue;
      }
    }
    index++;
    if (char === ';') {
      result.push({ start: first, end: index, text: sql.slice(first, index) });
      first = null;
    }
  }
  assert.equal(first, null, 'Unexpected unterminated top-level SQL statement');
  return result;
}

export function withoutOuterTransaction(original) {
  const all = statements(original);
  assert.ok(all.length > 2, 'Expected transaction around substantive SQL');
  const first = all[0], last = all.at(-1);
  assert.match(first.text, /^begin\s*;$/i, 'First SQL statement must be BEGIN');
  assert.match(last.text, /^commit\s*;$/i, 'Final SQL statement must be COMMIT');
  // Remove the two statement lines including their newline; all other bytes
  // (including comments, blank lines and PL/pgSQL bodies) remain untouched.
  for (const statement of [first, last]) {
    assert.ok(statement.start === 0 || original[statement.start - 1] === '\n');
    assert.equal(original[statement.end], '\n');
  }
  return original.slice(0, first.start) + original.slice(first.end + 1, last.start) + original.slice(last.end + 1);
}

export function proveWrapperOnly(original, corrected, { pinOriginal = true } = {}) {
  if (pinOriginal) assert.equal(sha256(original), originalFingerprint, 'Unrecognized original migration');
  assert.equal(corrected, withoutOuterTransaction(original), 'Only the outer BEGIN/COMMIT lines may change');
  const before = statements(original), after = statements(corrected);
  assert.deepEqual(after.map((item) => item.text), before.slice(1, -1).map((item) => item.text));
  assert.ok(after.every((item) => !/^(?:begin|commit|rollback)\s*;$/i.test(item.text)), 'Unexpected top-level transaction control');
  return {
    original_sha256: sha256(original), corrected_sha256: sha256(corrected),
    original_statements: before.length, corrected_statements: after.length,
    statement_bodies_byte_identical: true, other_bytes_preserved: true,
    removed: ['outer begin; line', 'final commit; line'],
  };
}

// The owner subsequently authorized versioned compatibility projections in
// this still-unapplied migration. Keep the historical wrapper-only proof above,
// then independently pin the exact reviewed final SQL and transaction boundary.
export function proveFinalMigration(sql) {
  assert.equal(sha256(sql), finalFingerprint, 'Unreviewed final migration bytes');
  const all = statements(sql);
  assert.ok(all.every(item => !/^(?:begin|commit|rollback)\s*;$/i.test(item.text)), 'Unexpected top-level transaction control');
  for (const identity of ['app.storefront_content_read_v1', 'app.get_restaurant_storefront_content_v1',
    'public.get_restaurant_storefront_content_v1', 'app.list_storefront_content_media_v1',
    'public.list_storefront_content_media_v1', 'public.storefront_menu_v4']) {
    assert.ok(!all.some(item => item.text.toLowerCase().startsWith(`create or replace function ${identity}(`) ||
      item.text.toLowerCase().startsWith(`create function ${identity}(`)), `Legacy reader must remain unchanged: ${identity}`);
  }
  return { final_sha256: sha256(sql), final_statements: all.length, no_embedded_transaction: true, legacy_readers_unchanged: true };
}

export function requireEphemeralCi(env) {
  assert.equal(env.GITHUB_ACTIONS, 'true', 'Only a disposable GitHub Actions runner is authorized');
  assert.equal(env.CI, 'true');
  assert.equal(env.CINEMATIC_EPHEMERAL, 'BIZBOT-STOREFRONT-CINEMATIC-001B', 'Explicit isolated integration lane marker required');
  assert.ok(env.GITHUB_RUN_ID && /^\d+$/.test(env.GITHUB_RUN_ID));
  assert.ok(env.RUNNER_TEMP && env.GITHUB_WORKSPACE);
  for (const name of ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'SUPABASE_DB_URL', 'SUPABASE_WORKDIR',
    'SUPABASE_SERVICES_HOSTNAME', 'DOCKER_HOST', 'DOCKER_CONTEXT', 'PGHOST', 'PGSERVICE', 'PGSERVICEFILE']) {
    assert.ok(!env[name], `Unexpected endpoint/credential override: ${name}`);
  }
}

// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-CINEMATIC-PROOF-001: the exact reviewed
// migration sequence. The #379 target must follow its exact predecessor and the
// exact 183-migration prefix of main 0df86dcb, then 001D and exactly the two
// reviewed PR380 migrations (product helpers before scene). Anything else is refused
// until a reviewed change extends this pin: it is not a generic mechanism.
export const predecessorName = '20261102015942_bizbot_storefront_seo_discovery_001.sql';
export const predecessorVersion = '20261102015942';
export const prefixNamesFingerprint = '6ee60a7fc86607ebbcd69492f551f673622336c4476823ee8a2c014106f15643';
export const followUpName = '20261104141959_bizbot_zcredit_001d_server_ledger.sql';
export const followUpVersion = '20261104141959';
export const followUpFingerprint = '468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e';
// Every function the reviewed #379 target creates or replaces.
export const followupMigrations = Object.freeze([
  Object.freeze({ name: '20261104154000_bizbot_storefront_visual_parity_product_media.sql',
    sha256: 'a901a709970b4629b22357743831aab687c2882fe066776dd7913b82c29c77d5' }),
  Object.freeze({ name: '20261104155000_bizbot_storefront_visual_parity_scene.sql',
    sha256: '7bfac52a707b20fdf9b67a466d84290a7565fe574850ce1e992c093d5f19b520' }),
]);


export const targetFunctions = [
  'app.get_restaurant_storefront_content_v2', 'app.list_storefront_content_media_v2', 'app.set_restaurant_storefront_content_v1',
  'app.storefront_content_document_shape_v1', 'app.storefront_content_media_in_use_v1', 'app.storefront_content_read_v2',
  'app.storefront_content_repoint_media_v1', 'public.get_restaurant_storefront_content_v2',
  'public.list_storefront_content_media_v2', 'public.storefront_menu_v5',
];
const migrationFileName = /^\d{14}_[a-z0-9][a-z0-9_]*\.sql$/;
// The supported runner applies each file atomically; top-level transaction
// control would split that apply. Dollar-quoted PL/pgSQL BEGIN/END never matches.
const transactionControl = /^(?:begin|start\s+transaction|commit|end|rollback|abort|savepoint|release|prepare\s+transaction)\b/i;

export function topLevelTransactionControl(sql) {
  return statements(sql).filter((item) => transactionControl.test(item.text)).map((item) => item.text);
}

export function proveFollowUpMigration(bytes) {
  assert.ok(Buffer.isBuffer(bytes), 'Migration sources must be raw bytes');
  // Structure first, then the reviewed bytes, so that each refusal names its cause.
  const sql = bytes.toString('utf8');
  assert.ok(topLevelTransactionControl(sql).length === 0, 'Unexpected top-level transaction control in the 001D follow-up');
  assert.equal(sha256(bytes), followUpFingerprint, 'Unreviewed 001D follow-up bytes');
  return { follow_up_sha256: sha256(bytes), follow_up_statements: statements(sql).length, follow_up_no_embedded_transaction: true };
}

// `sources` is the migration directory as [name, raw bytes] pairs in the order
// the supported CLI applies them (byte-wise file-name order). Nothing is sorted
// or filtered here: the caller's exact listing and exact bytes are proved.
export function proveMigrationSequence(sources) {
  assert.ok(Array.isArray(sources) && sources.length > 0, 'Expected the migration directory listing');
  assert.ok(sources.every((entry) => Array.isArray(entry) && entry.length === 2 && Buffer.isBuffer(entry[1])),
    'Migration sources must be raw bytes');
  const names = sources.map(([name]) => name);
  for (const name of names) {
    assert.match(String(name), migrationFileName, 'Migration file names must be a 14-digit version, a lower-case name and .sql');
  }
  const versions = names.map((name) => name.slice(0, 14));
  assert.equal(new Set(versions).size, versions.length, 'Duplicate migration version');
  assert.ok(versions.every((version, index) => index === 0 || version > versions[index - 1]),
    'Migration versions must be strictly ascending');
  const index = names.indexOf(migrationName);
  assert.ok(index >= 0, 'Missing the exact #379 target migration');
  assert.equal(names[index - 1], predecessorName, 'The #379 target must directly follow its exact predecessor');
  const prefixNames = sha256(names.slice(0, index).join('\n'));
  assert.equal(prefixNames, prefixNamesFingerprint, 'Unreviewed migration sequence before the #379 target');
  const later = names.slice(index + 1);
  assert.ok(later.includes(followUpName), 'Missing the reviewed 001D follow-up migration');
  if (later[0] !== followUpName) {
    assert.ok(!later.includes(followUpName), 'Interleaved migration between the #379 target and the 001D follow-up');
    assert.fail('Unknown migration after the #379 target');
  }
  assert.deepEqual(later, [followUpName, ...followupMigrations.map(item => item.name)], 'Only the reviewed 001D then product and scene migrations may follow the #379 target');
  const bytes = new Map(sources);
  proveFinalMigration(bytes.get(migrationName).toString('utf8'));
  const followUp = proveFollowUpMigration(bytes.get(followUpName));
  const visualFollowups = followupMigrations.map(pin => {
    const bytes = new Map(sources).get(pin.name);
    assert.ok(Buffer.isBuffer(bytes), 'Visual follow-up migration sources must be raw bytes');
    assert.equal(topLevelTransactionControl(bytes.toString('utf8')).length, 0, 'Unexpected transaction control in a visual follow-up');
    assert.equal(sha256(bytes), pin.sha256, 'Unreviewed visual follow-up bytes');
    return { name: pin.name, version: pin.name.slice(0, 14), sha256: pin.sha256,
      statements: statements(bytes.toString('utf8')).length, no_embedded_transaction: true };
  });
  // A renamed or copied migration cannot carry the reviewed bytes elsewhere.
  for (const [name, value] of sources) {
    const digest = sha256(value);
    for (const pin of followupMigrations) assert.ok(name === pin.name || digest !== pin.sha256, 'Reviewed visual bytes may appear only under their pinned name');
    assert.ok(name === migrationName || digest !== finalFingerprint, 'The reviewed #379 target bytes may appear only under its pinned name');
    assert.ok(name === followUpName || digest !== followUpFingerprint, 'The reviewed 001D bytes may appear only under their pinned name');
  }
  return {
    target_prefix: names.slice(0, index + 1),
    visual_followups: visualFollowups,
    summary: { migrations: names.length, before_target: index, predecessor: predecessorName, target: migrationName,
      later_than_target: later, prefix_names_sha256: prefixNames, ...followUp, visual_followups: visualFollowups },
  };
}

// The disposable workdir of the late-failure and target-only phases: the exact
// sources before the #379 target, then the given target bytes (the broken copy,
// or the tracked bytes). The 001D follow-up is never part of it.
export function targetPrefixSources(sources, targetBytes) {
  assert.ok(Buffer.isBuffer(targetBytes), 'Migration sources must be raw bytes');
  const { target_prefix: prefix } = proveMigrationSequence(sources);
  const bytes = new Map(sources);
  return prefix.map((name) => [name, name === migrationName ? targetBytes : bytes.get(name)]);
}
