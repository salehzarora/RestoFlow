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
