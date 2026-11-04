// BIZBOT-STOREFRONT-CINEMATIC-001B. Run before any acceptance fixtures.
// Uses only the pinned, supported Supabase local runner. No hosted API or URL.
// The intentional failure exists only in a disposable copy of the migration.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  migrationName, migrationVersion, historicalMigrationName, originalCommit, wrapperOnlyCommit, proveWrapperOnly, proveFinalMigration,
  requireEphemeralCi, sha256, proveMigrationSequence,
} from './cinematic_001b_migration_contract.mjs';

requireEphemeralCi(process.env); // Must precede subprocesses, including Docker.
assert.equal(process.argv.length, 2, 'This runner accepts no endpoint or override arguments');
const root = fileURLToPath(new URL('../../../', import.meta.url));
assert.equal(await realpath(root), await realpath(process.env.GITHUB_WORKSPACE));
const artifactDir = resolve(process.env.CINEMATIC_ARTIFACT_DIR ?? join(process.env.RUNNER_TEMP, 'cinematic-public'));
assert.ok(artifactDir.startsWith(resolve(process.env.RUNNER_TEMP) + '/'), 'Artifacts must stay in the disposable runner directory');
await mkdir(artifactDir, { recursive: true, mode: 0o700 });
const container = 'supabase_db_RestoFlow';
let phase = 'preflight';
const receipt = { status: 'FAIL', phase, real_supabase_runner: true, local_only: true };
let temporary;

function command(program, args, options = {}) {
  try {
    return { code: 0, stdout: execFileSync(program, args, {
      cwd: root, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 128 * 1024 * 1024, timeout: 300_000, ...options,
    }), stderr: '' };
  } catch (error) {
    if (typeof error.status !== 'number') throw new Error(`${program} could not complete`);
    return { code: error.status, stdout: String(error.stdout ?? ''), stderr: String(error.stderr ?? '') };
  }
}
function checked(program, args, options) {
  const result = command(program, args, options);
  assert.equal(result.code, 0, `${program} failed during ${phase}; raw output intentionally not persisted`);
  return result.stdout;
}
function sql(query) {
  return checked('docker', ['exec', '-i', container, 'psql', '-X', '-qAt', '--no-password', '-h', '/var/run/postgresql', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], { input: query }).trim();
}
function schemaSnapshot() {
  // pg_dump 17 emits a random \restrict key. Removing these transport sentinels
  // does not remove SQL, comments, ACLs, RLS, definitions, ownership or ordering.
  return checked('docker', ['exec', container, 'pg_dump', '--schema-only', '--schema=app', '--schema=public', '--schema=supabase_migrations', '-h', '/var/run/postgresql', '-U', 'supabase_admin', '-d', 'postgres'])
    .split('\n').filter((line) => !/^\\(?:un)?restrict [A-Za-z0-9]+$/.test(line)).join('\n');
}
const historyQuery = "select coalesce(jsonb_agg(to_jsonb(h) order by version),'[]'::jsonb)::text from supabase_migrations.schema_migrations h;";
const legacyReadersQuery = `select jsonb_agg(jsonb_build_object(
  'identity', p.oid::regprocedure::text, 'definition', pg_get_functiondef(p.oid),
  'acl', p.proacl, 'owner', p.proowner) order by p.oid::regprocedure::text)::text
  from pg_proc p where p.oid in (
    'app.storefront_content_read_v1(uuid,uuid,uuid,text,text,text,jsonb)'::regprocedure,
    'app.get_restaurant_storefront_content_v1(uuid,uuid)'::regprocedure,
    'public.get_restaurant_storefront_content_v1(uuid,uuid)'::regprocedure,
    'app.list_storefront_content_media_v1(uuid,uuid)'::regprocedure,
    'public.list_storefront_content_media_v1(uuid,uuid)'::regprocedure,
    'public.storefront_menu_v4(text)'::regprocedure);`;
const readinessQuery = `select json_build_object(
  'column', exists(select 1 from pg_attribute where attrelid='app.storefront_content_profiles'::regclass and attname='appearance' and not attisdropped),
  'rpc', to_regprocedure('public.get_restaurant_storefront_content_v2(uuid,uuid)') is not null,
  'media_rpc', to_regprocedure('public.list_storefront_content_media_v2(uuid,uuid)') is not null,
  'menu_rpc', to_regprocedure('public.storefront_menu_v5(text)') is not null,
  'history', (select count(*) from supabase_migrations.schema_migrations where version='${migrationVersion}'))::text;`;
const followupReadinessQuery = `select json_build_object(
  'content_v3', to_regprocedure('public.get_restaurant_storefront_content_v3(uuid,uuid)') is not null,
  'menu_v6', to_regprocedure('public.storefront_menu_v6(text)') is not null,
  'derivatives', to_regclass('app.storefront_product_derivatives') is not null,
  'selections', to_regclass('app.storefront_product_selections') is not null,
  'original', to_regprocedure('public.get_storefront_product_original_v1(uuid,uuid,uuid)') is not null,
  'register', to_regprocedure('public.register_storefront_product_derivative_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,bigint)') is not null,
  'source', to_regprocedure('public.get_storefront_product_source_v1(uuid,uuid,uuid)') is not null,
  'stage', to_regprocedure('public.stage_storefront_product_media_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,integer,integer,integer)') is not null,
  'finalize', to_regprocedure('public.finalize_storefront_product_media_v1(uuid,uuid,uuid,uuid)') is not null,
  'select', to_regprocedure('public.select_storefront_product_derivative_v1(uuid,uuid,uuid,uuid)') is not null)::text;`;
const followupReadiness = Object.fromEntries(['content_v3', 'menu_v6', 'derivatives', 'selections',
  'original', 'register', 'source', 'stage', 'finalize', 'select'].map(name => [name, true]));
const noFollowupReadiness = Object.fromEntries(Object.keys(followupReadiness).map(name => [name, false]));
const migrationNames = async () => (await readdir(join(root, 'supabase/migrations')))
  .filter(name => /^\d+_.+\.sql$/.test(name)).sort();

try {
  assert.equal(checked('supabase', ['--version']).trim(), '2.107.0', 'Use the project-pinned CLI');
  const upHelp = checked('supabase', ['migration', 'up', '--help']);
  const resetHelp = checked('supabase', ['db', 'reset', '--help']);
  assert.match(upHelp, /--local/);
  for (const flag of ['--local', '--version', '--no-seed']) assert.ok(resetHelp.includes(flag));
  const dockerEndpoint = checked('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}']).trim();
  assert.equal(dockerEndpoint, 'unix:///var/run/docker.sock', 'Docker must be the runner-local daemon');
  const [metadata] = JSON.parse(checked('docker', ['inspect', container]));
  assert.equal(metadata.Name, `/${container}`);
  assert.equal(metadata.State.Running, true);
  assert.match(metadata.Config.Image, /(?:^|\/)supabase\/postgres:17\./);
  assert.notEqual(metadata.HostConfig.NetworkMode, 'host');
  const config = await readFile(join(root, 'supabase/config.toml'), 'utf8');
  assert.match(config, /^project_id = "RestoFlow"$/m);
  assert.match(config, /^\[db\][\s\S]*?^port = 54322$/m);
  assert.equal(sql('select (select count(*) from auth.users)+(select count(*) from public.restaurants)+(select count(*) from public.orders);'), '0', 'Only a fresh stack before fixtures may be reset');
  const migrationPath = join(root, 'supabase/migrations', migrationName);
  const corrected = await readFile(migrationPath, 'utf8');
  const original = checked('git', ['show', `${originalCommit}:supabase/migrations/${historicalMigrationName}`]);
  const historical = checked('git', ['show', `${wrapperOnlyCommit}:supabase/migrations/${historicalMigrationName}`]);
  Object.assign(receipt, { historical_wrapper_only: proveWrapperOnly(original, historical) }, proveFinalMigration(corrected), {
    tested_commit: checked('git', ['rev-parse', 'HEAD']).trim(),
    tested_tree: checked('git', ['rev-parse', 'HEAD^{tree}']).trim(),
    cli_version: '2.107.0',
  });
  const migrations = await migrationNames();
  const sources = new Map(await Promise.all(migrations.map(async name => [name,
    await readFile(join(root, 'supabase/migrations', name), 'utf8')])));
  const plan = proveMigrationSequence(migrations, sources);
  receipt.previous_version = plan.previousVersion;
  receipt.target_prefix = { last_migration: plan.prefixNames.at(-1), count: plan.prefixNames.length };
  receipt.reviewed_followups = plan.followups;
  const unchangedSources = async () => {
    assert.deepEqual(await migrationNames(), migrations, 'Migration file sequence must remain unchanged');
    for (const [name, contents] of sources) {
      assert.equal(await readFile(join(root, 'supabase/migrations', name), 'utf8'), contents, 'Every tracked migration must remain byte-identical');
    }
  };

  phase = 'prepare_before_target';
  checked('supabase', ['db', 'reset', '--local', '--version', plan.previousVersion, '--no-seed', '--yes']);
  assert.deepEqual(JSON.parse(sql(readinessQuery)), { column: false, rpc: false, media_rpc: false, menu_rpc: false, history: 0 });
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), noFollowupReadiness, 'Followup surfaces must be absent before the target');
  const beforeSchema = schemaSnapshot();
  const beforeHistory = sql(historyQuery);
  const beforeLegacyReaders = sql(legacyReadersQuery);
  receipt.before_schema_sha256 = sha256(beforeSchema);
  receipt.before_history_sha256 = sha256(beforeHistory);
  receipt.legacy_readers_before_sha256 = sha256(beforeLegacyReaders);
  temporary = await mkdtemp(join(process.env.RUNNER_TEMP, 'cinematic-migration-failure-'));
  await mkdir(join(temporary, 'supabase/migrations'), { recursive: true });
  await writeFile(join(temporary, 'supabase/config.toml'), config);
  // Both target attempts use the official runner over this exact prefix. Later
  // migrations cannot alter the catalog before the target's preservation proof.
  for (const name of plan.prefixNames) {
    await copyFile(join(root, 'supabase/migrations', name), join(temporary, 'supabase/migrations', name));
    assert.equal(await readFile(join(temporary, 'supabase/migrations', name), 'utf8'), sources.get(name));
  }
  assert.deepEqual((await readdir(join(temporary, 'supabase/migrations'))).sort(), plan.prefixNames);
  // Function declarations above have executed when this block runs. Its
  // deliberate exception must roll them, their ACLs and migration history back.
  const failure = `\ndo $cinematic_late_failure$\nbegin
 if not exists(select 1 from pg_attribute where attrelid='app.storefront_content_profiles'::regclass and attname='appearance' and not attisdropped)
  or to_regprocedure('public.get_restaurant_storefront_content_v2(uuid,uuid)') is null
  or to_regprocedure('public.list_storefront_content_media_v2(uuid,uuid)') is null
  or to_regprocedure('public.storefront_menu_v5(text)') is null then
  raise exception 'BIZBOT_CINEMATIC_FAILURE_PRECONDITION';
 end if;
 raise exception 'BIZBOT_CINEMATIC_LATE_FAILURE' using errcode='P0001';
end;\n$cinematic_late_failure$;\n`;
  await writeFile(join(temporary, 'supabase/migrations', migrationName), corrected + failure);
  phase = 'intentional_late_failure';
  const failed = command('supabase', ['migration', 'up', '--local', '--workdir', temporary]);
  assert.notEqual(failed.code, 0, 'The disposable late-failure migration must fail');
  assert.match(failed.stderr + failed.stdout, /ERROR: BIZBOT_CINEMATIC_LATE_FAILURE\b/);
  assert.match(failed.stderr + failed.stdout, /SQLSTATE P0001/);
  receipt.expected_failure = { exit_code: failed.code, marker: 'BIZBOT_CINEMATIC_LATE_FAILURE', sqlstate: 'P0001' };
  phase = 'assert_atomic_rollback';
  assert.deepEqual(JSON.parse(sql(readinessQuery)), { column: false, rpc: false, media_rpc: false, menu_rpc: false, history: 0 });
  assert.equal(schemaSnapshot(), beforeSchema, 'Schema (including replaced functions and ACLs) must roll back');
  assert.equal(sql(historyQuery), beforeHistory, 'Entire migration history must roll back with schema');
  receipt.schema_and_history_rollback = 'PASS';

  phase = 'apply_corrected_target';
  await writeFile(join(temporary, 'supabase/migrations', migrationName), corrected);
  checked('supabase', ['migration', 'up', '--local', '--workdir', temporary]);
  assert.deepEqual(JSON.parse(sql(readinessQuery)), { column: true, rpc: true, media_rpc: true, menu_rpc: true, history: 1 });
  assert.equal(await readFile(migrationPath, 'utf8'), corrected, 'Tracked migration must remain unmodified');
  const afterLegacyReaders = sql(legacyReadersQuery);
  assert.equal(afterLegacyReaders, beforeLegacyReaders, 'Legacy reader definitions, ACLs and owners must remain byte-identical');
  receipt.target_legacy_readers_after_sha256 = sha256(afterLegacyReaders);
  receipt.target_legacy_reader_catalog_preservation = 'PASS';
  receipt.successful_target_application = 'PASS';
  receipt.target_after_schema_sha256 = sha256(schemaSnapshot());
  receipt.target_after_history_sha256 = sha256(sql(historyQuery));
  const targetHistory = JSON.parse(sql(historyQuery));
  assert.ok(plan.followups.every(item => !targetHistory.some(row => row.version === item.version)), 'Followups must not execute during the target proof');
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), noFollowupReadiness, 'Target-only application must not install followup surfaces');
  await unchangedSources();

  phase = 'apply_reviewed_followups';
  checked('supabase', ['migration', 'up', '--local']);
  const finalHistory = JSON.parse(sql(historyQuery));
  assert.deepEqual(finalHistory.filter(row => row.version <= migrationVersion), targetHistory, 'Existing migration history must remain unchanged');
  assert.deepEqual(finalHistory.filter(row => row.version > migrationVersion).map(row => row.version),
    plan.followups.map(item => item.version), 'Each reviewed followup must have exactly one history entry, with no others');
  assert.equal(finalHistory.filter(row => row.version === migrationVersion).length, 1);
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), followupReadiness, 'Reviewed v3/v6 and complete product RPC surface must be ready');
  await unchangedSources();
  receipt.followup_history_once = 'PASS';
  receipt.followup_readiness = followupReadiness;
  receipt.migration_sources_unchanged = 'PASS';
  receipt.successful_followup_application = 'PASS';
  receipt.after_schema_sha256 = sha256(schemaSnapshot());
  receipt.after_history_sha256 = sha256(sql(historyQuery));
  receipt.status = 'PASS';
  phase = 'complete';
} catch (error) {
  // Fixed assertions only; never persist a command's environment or full output.
  receipt.failure = String(error.message).split('\n')[0];
  process.exitCode = 1;
} finally {
  receipt.phase = phase;
  await writeFile(join(artifactDir, 'migration-atomicity.json'), JSON.stringify(receipt, null, 2) + '\n', { mode: 0o600 });
  if (temporary) await rm(temporary, { recursive: true, force: true });
  console.log(JSON.stringify(receipt));
}
