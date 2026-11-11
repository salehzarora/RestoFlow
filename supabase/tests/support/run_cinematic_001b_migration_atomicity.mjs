// BIZBOT-STOREFRONT-CINEMATIC-001B. Run before any acceptance fixtures.
// Uses only the pinned, supported Supabase local runner. No hosted API or URL.
// The intentional failure exists only in a disposable copy of the migration.
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-CINEMATIC-PROOF-001: the late failure and
// the target-only apply run in disposable workdirs that hold exactly the prefix
// ending at the #379 target; the one reviewed follow-up (001D) is then applied
// alone from an exact disposable prefix, then the pinned product, scene and background follow-ups.
// BIZBOT-STOREFRONT-CINEMATIC-P2-G1-PIN-001: the three reviewed successors after them (the #386
// POS duty migration, the P2 G1 payment migration and the site theme) are pinned by the contract, applied whenever the
// complete directory is applied (the normal database suite, and the stack start before this runner
// resets it), and excluded from every historical plan built here.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  migrationName, migrationVersion, historicalMigrationName, originalCommit, wrapperOnlyCommit, proveWrapperOnly, proveFinalMigration,
  requireEphemeralCi, sha256, predecessorVersion, followUpName, followUpVersion, targetFunctions, proveMigrationSequence,
  targetPrefixSources, visualReleaseSources, siteThemeSuccessor, siteThemeReleaseSources,
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
const temporaries = [];

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
  'menu_v7', to_regprocedure('public.storefront_menu_v7(text)') is not null,
  'background', to_regclass('app.storefront_background_variants') is not null,
  'background_source', to_regprocedure('public.get_storefront_background_source_v1(uuid,uuid,uuid,uuid)') is not null,
  'background_stage', to_regprocedure('public.stage_storefront_background_variant_v1(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,integer,integer,integer)') is not null,
  'background_finalize', to_regprocedure('public.finalize_storefront_background_variant_v1(uuid,uuid,uuid,uuid)') is not null,
  'derivatives', to_regclass('app.storefront_product_derivatives') is not null,
  'selections', to_regclass('app.storefront_product_selections') is not null,
  'original', to_regprocedure('public.get_storefront_product_original_v1(uuid,uuid,uuid)') is not null,
  'register', to_regprocedure('public.register_storefront_product_derivative_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,bigint)') is not null,
  'source', to_regprocedure('public.get_storefront_product_source_v1(uuid,uuid,uuid)') is not null,
  'stage', to_regprocedure('public.stage_storefront_product_media_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,integer,integer,integer)') is not null,
  'finalize', to_regprocedure('public.finalize_storefront_product_media_v1(uuid,uuid,uuid,uuid)') is not null,
  'select', to_regprocedure('public.select_storefront_product_derivative_v1(uuid,uuid,uuid,uuid)') is not null)::text;`;
const followupReadiness = Object.fromEntries(['content_v3', 'menu_v6', 'derivatives', 'selections',
  'menu_v7', 'background', 'background_source', 'background_stage', 'background_finalize',
  'original', 'register', 'source', 'stage', 'finalize', 'select'].map(name => [name, true]));
const noFollowupReadiness = Object.fromEntries(Object.keys(followupReadiness).map(name => [name, false]));
const siteThemeReadinessQuery = `select json_build_object(
  'content_v4', to_regprocedure('public.get_restaurant_storefront_content_v4(uuid,uuid)') is not null,
  'menu_v8', to_regprocedure('public.storefront_menu_v8(text)') is not null)::text;`;
const siteThemeGrantsQuery = `select json_build_object(
  'content_v4_authenticated', has_function_privilege('authenticated', 'public.get_restaurant_storefront_content_v4(uuid,uuid)', 'EXECUTE'),
  'menu_v8_anon', has_function_privilege('anon', 'public.storefront_menu_v8(text)', 'EXECUTE'),
  'menu_v8_authenticated', has_function_privilege('authenticated', 'public.storefront_menu_v8(text)', 'EXECUTE'))::text;`;
const historyVersionsQuery = "select coalesce(jsonb_agg(version order by version),'[]'::jsonb)::text from supabase_migrations.schema_migrations;";
const historyThroughTargetQuery = `select coalesce(jsonb_agg(to_jsonb(h) order by version),'[]'::jsonb)::text
  from supabase_migrations.schema_migrations h where version <= '${migrationVersion}';`;
// Every surface the #379 target creates or replaces: its functions (definition,
// ACL, owner, comment), its appearance column and the table's constraints.
const targetSurfacesQuery = `select jsonb_build_object(
  'functions', (select coalesce(jsonb_agg(jsonb_build_object(
      'name', n.nspname || '.' || p.proname, 'identity', p.oid::regprocedure::text, 'definition', pg_get_functiondef(p.oid),
      'acl', p.proacl, 'owner', p.proowner, 'comment', obj_description(p.oid, 'pg_proc'))
      order by p.oid::regprocedure::text), '[]'::jsonb)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname || '.' || p.proname) = any(array[${targetFunctions.map((name) => `'${name}'`).join(',')}])),
  'appearance', (select jsonb_build_object('type', format_type(a.atttypid, a.atttypmod), 'not_null', a.attnotnull,
      'default', pg_get_expr(d.adbin, d.adrelid), 'acl', a.attacl, 'comment', col_description(a.attrelid, a.attnum))
    from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = 'app.storefront_content_profiles'::regclass and a.attname = 'appearance' and not a.attisdropped),
  'constraints', (select coalesce(jsonb_agg(jsonb_build_object('name', c.conname, 'definition', pg_get_constraintdef(c.oid))
      order by c.conname), '[]'::jsonb)
    from pg_constraint c where c.conrelid = 'app.storefront_content_profiles'::regclass))::text;`;
const versionsOf = (names) => names.map((name) => name.slice(0, 14));
async function readMigrationSources(directory) {
  // Raw bytes in the supported CLI's byte-wise file-name order; regular files only.
  const entries = await readdir(directory, { withFileTypes: true });
  assert.ok(entries.every((entry) => entry.isFile()), 'The migration directory may hold only regular files');
  const names = entries.map((entry) => entry.name).sort();
  return Promise.all(names.map(async (name) => [name, await readFile(join(directory, name))]));
}

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
  const migrationsDirectory = join(root, 'supabase/migrations');
  const migrationPath = join(migrationsDirectory, migrationName);
  Object.assign(receipt, {
    tested_commit: checked('git', ['rev-parse', 'HEAD']).trim(),
    tested_tree: checked('git', ['rev-parse', 'HEAD^{tree}']).trim(),
    cli_version: '2.107.0',
  });
  // The exact reviewed sequence and its raw bytes replace the newest-migration guard.
  const sources = await readMigrationSources(migrationsDirectory);
  const sequence = proveMigrationSequence(sources);
  const sourceBytes = new Map(sources);
  const corrected = sourceBytes.get(migrationName).toString('utf8');
  const original = checked('git', ['show', `${originalCommit}:supabase/migrations/${historicalMigrationName}`]);
  const historical = checked('git', ['show', `${wrapperOnlyCommit}:supabase/migrations/${historicalMigrationName}`]);
  Object.assign(receipt, { historical_wrapper_only: proveWrapperOnly(original, historical) }, proveFinalMigration(corrected),
    { migration_sequence: sequence.summary });
  const beforeTarget = sequence.target_prefix.slice(0, -1);
  const previousVersion = predecessorVersion;
  receipt.previous_version = previousVersion;
  // A disposable workdir that holds exactly the prefix ending at the #379
  // target (the follow-up is never part of it), verified before use.
  const prefixWorkdir = async (prefix, targetBytes) => {
    const workdir = await mkdtemp(join(process.env.RUNNER_TEMP, prefix));
    temporaries.push(workdir);
    await mkdir(join(workdir, 'supabase/migrations'), { recursive: true });
    await writeFile(join(workdir, 'supabase/config.toml'), config);
    const plan = targetPrefixSources(sources, targetBytes);
    for (const [name, bytes] of plan) await writeFile(join(workdir, 'supabase/migrations', name), bytes);
    const written = await readMigrationSources(join(workdir, 'supabase/migrations'));
    assert.deepEqual(written.map(([name]) => name), sequence.target_prefix, 'The disposable workdir must hold exactly the prefix ending at the #379 target');
    assert.ok(written.every(([, bytes], index) => bytes.equals(plan[index][1])), 'The disposable workdir must hold exactly the planned bytes');
    return workdir;
  };

  phase = 'prepare_before_target';
  checked('supabase', ['db', 'reset', '--local', '--version', previousVersion, '--no-seed', '--yes']);
  assert.deepEqual(JSON.parse(sql(readinessQuery)), { column: false, rpc: false, media_rpc: false, menu_rpc: false, history: 0 });
  assert.deepEqual(JSON.parse(sql(historyVersionsQuery)), versionsOf(beforeTarget), 'The reset must stop exactly at the #379 predecessor');
  const beforeSchema = schemaSnapshot();
  const beforeHistory = sql(historyQuery);
  const beforeLegacyReaders = sql(legacyReadersQuery);
  receipt.before_schema_sha256 = sha256(beforeSchema);
  receipt.before_history_sha256 = sha256(beforeHistory);
  receipt.legacy_readers_before_sha256 = sha256(beforeLegacyReaders);
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
  const failureWorkdir = await prefixWorkdir('cinematic-migration-failure-', Buffer.from(corrected + failure));
  phase = 'intentional_late_failure';
  const failed = command('supabase', ['migration', 'up', '--local', '--workdir', failureWorkdir]);
  assert.notEqual(failed.code, 0, 'The disposable late-failure migration must fail');
  assert.match(failed.stderr + failed.stdout, /ERROR: BIZBOT_CINEMATIC_LATE_FAILURE\b/);
  assert.match(failed.stderr + failed.stdout, /SQLSTATE P0001/);
  receipt.expected_failure = { exit_code: failed.code, marker: 'BIZBOT_CINEMATIC_LATE_FAILURE', sqlstate: 'P0001' };
  phase = 'assert_atomic_rollback';
  assert.deepEqual(JSON.parse(sql(readinessQuery)), { column: false, rpc: false, media_rpc: false, menu_rpc: false, history: 0 });
  assert.equal(schemaSnapshot(), beforeSchema, 'Schema (including replaced functions and ACLs) must roll back');
  assert.equal(sql(historyQuery), beforeHistory, 'Entire migration history must roll back with schema');
  receipt.schema_and_history_rollback = 'PASS';
  assert.ok((await readFile(migrationPath)).equals(sourceBytes.get(migrationName)), 'Tracked migration must remain unmodified');
  receipt.tracked_target_unchanged_after_failure = 'PASS';

  phase = 'apply_target_alone';
  const targetWorkdir = await prefixWorkdir('cinematic-migration-target-', sourceBytes.get(migrationName));
  checked('supabase', ['migration', 'up', '--local', '--workdir', targetWorkdir]);
  assert.deepEqual(JSON.parse(sql(readinessQuery)), { column: true, rpc: true, media_rpc: true, menu_rpc: true, history: 1 });
  assert.deepEqual(JSON.parse(sql(historyVersionsQuery)), versionsOf(sequence.target_prefix), 'Only the #379 target may be applied in this phase');
  assert.ok((await readFile(migrationPath)).equals(sourceBytes.get(migrationName)), 'Tracked migration must remain unmodified');
  const afterLegacyReaders = sql(legacyReadersQuery);
  assert.equal(afterLegacyReaders, beforeLegacyReaders, 'Legacy reader definitions, ACLs and owners must remain byte-identical');
  receipt.legacy_readers_after_sha256 = sha256(afterLegacyReaders);
  receipt.legacy_reader_catalog_preservation = 'PASS';
  receipt.successful_target_application = 'PASS';
  const targetSurfaces = sql(targetSurfacesQuery);
  const surfaces = JSON.parse(targetSurfaces);
  assert.deepEqual([...new Set(surfaces.functions.map((item) => item.name))].sort(), [...targetFunctions].sort(),
    'Every function of the #379 target must exist');
  assert.ok(surfaces.appearance && surfaces.constraints.length > 0, 'The #379 appearance column and its table constraints must exist');
  const targetOnlyHistory = sql(historyQuery);
  receipt.target_only_schema_sha256 = sha256(schemaSnapshot());
  receipt.target_only_history_sha256 = sha256(targetOnlyHistory);
  receipt.target_surfaces_sha256 = sha256(targetSurfaces);

  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), noFollowupReadiness, 'Target-only application must not install PR380 surfaces');
  phase = 'apply_reviewed_follow_up';
  // Apply payment alone before any visual migration can replace target readers.
  const paymentWorkdir = await prefixWorkdir('cinematic-migration-payment-', sourceBytes.get(migrationName));
  await writeFile(join(paymentWorkdir, 'supabase/migrations', followUpName), sourceBytes.get(followUpName));
  const paymentSources = await readMigrationSources(join(paymentWorkdir, 'supabase/migrations'));
  assert.deepEqual(paymentSources.map(([name]) => name), [...sequence.target_prefix, followUpName]);
  assert.ok(paymentSources.every(([name, bytes]) => bytes.equals(sourceBytes.get(name))), 'Payment workdir must retain exact reviewed bytes');
  checked('supabase', ['migration', 'up', '--local', '--workdir', paymentWorkdir]);
  const appliedVersions = JSON.parse(sql(historyVersionsQuery));
  assert.deepEqual(appliedVersions, versionsOf([...sequence.target_prefix, followUpName]),
    'Exactly one 001D history row and no other migration later than #379');
  receipt.follow_up_history_rows = appliedVersions.filter((version) => version === followUpVersion).length;
  // Large values: compare without generating a diff; the receipt keeps the message only.
  assert.ok(sql(historyThroughTargetQuery) === targetOnlyHistory, 'The #379 target and every earlier history row must remain unchanged');
  assert.deepEqual(JSON.parse(sql(readinessQuery)), { column: true, rpc: true, media_rpc: true, menu_rpc: true, history: 1 });
  assert.ok(sql(legacyReadersQuery) === beforeLegacyReaders, 'Legacy reader definitions, ACLs and owners must remain byte-identical');
  assert.ok(sql(targetSurfacesQuery) === targetSurfaces, 'The #379 target surfaces must remain unchanged');
  receipt.target_and_legacy_readers_unchanged = 'PASS';
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), noFollowupReadiness, 'Payment alone must not install PR380 surfaces');
  receipt.follow_up_application = 'PASS';
  receipt.follow_up_schema_sha256 = sha256(schemaSnapshot());
  const paymentHistory = sql(historyQuery);
  receipt.follow_up_history_sha256 = sha256(paymentHistory);

  phase = 'apply_reviewed_visual_followups';
  // Extend the verified payment workdir through the last visual migration. A root-directory
  // migration up would apply unrelated successors as part of this historical proof.
  for (const { name } of sequence.visual_followups) {
    await writeFile(join(paymentWorkdir, 'supabase/migrations', name), sourceBytes.get(name));
  }
  const historicalSources = await readMigrationSources(join(paymentWorkdir, 'supabase/migrations'));
  assert.deepEqual(historicalSources.map(([name]) => name), sequence.historical_names);
  assert.ok(historicalSources.every(([name, bytes]) => bytes.equals(sourceBytes.get(name))), 'Historical workdir must retain exact reviewed bytes');
  checked('supabase', ['migration', 'up', '--local', '--workdir', paymentWorkdir]);
  const finalHistory = JSON.parse(sql(historyQuery));
  assert.deepEqual(finalHistory.filter(row => row.version <= followUpVersion), JSON.parse(paymentHistory),
    'Payment and all earlier history rows must remain unchanged');
  assert.deepEqual(finalHistory.map(row => row.version), versionsOf(sequence.historical_names),
    'Each pinned migration must have exactly one history row and no others');
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), followupReadiness, 'Reviewed content, menu, product and background RPCs must be ready');
  receipt.followup_history_once = 'PASS';
  receipt.followup_readiness = followupReadiness;
  receipt.successful_followup_application = 'PASS';
  receipt.after_schema_sha256 = sha256(schemaSnapshot());
  receipt.after_history_sha256 = sha256(sql(historyQuery));

  // The historical #379 / PR380 regression fixture: #379 and its visual follow-ups
  // applied, the payment migration 001D omitted. It reproduces that historical shape
  // afresh without changing payment (001D has since been applied on hosted, 2026-11-09;
  // the three pinned later successors are omitted here as well). The separate full
  // db-tests job still runs every payment suite/concurrency assertion against all
  // migrations; the real UI lifecycle uses the later site-theme extension of this
  // historical fixture. Both stacks are identified separately in the receipt; the phase name and receipt keys are unchanged.
  phase = 'prove_scoped_visual_release_without_pending_payment';
  checked('supabase', ['db', 'reset', '--local', '--version', migrationVersion, '--no-seed', '--yes']);
  assert.deepEqual(JSON.parse(sql(historyVersionsQuery)), versionsOf(sequence.target_prefix));
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), noFollowupReadiness);
  const releaseBaselineHistory = JSON.parse(sql(historyQuery));
  const releaseWorkdir = await mkdtemp(join(process.env.RUNNER_TEMP, 'cinematic-scoped-visual-release-'));
  temporaries.push(releaseWorkdir);
  await mkdir(join(releaseWorkdir, 'supabase/migrations'), { recursive: true });
  await writeFile(join(releaseWorkdir, 'supabase/config.toml'), config);
  const releasePlan = visualReleaseSources(sources);
  for (const [name, bytes] of releasePlan) await writeFile(join(releaseWorkdir, 'supabase/migrations', name), bytes);
  const releaseWritten = await readMigrationSources(join(releaseWorkdir, 'supabase/migrations'));
  assert.deepEqual(releaseWritten.map(([name]) => name), [...sequence.target_prefix, ...sequence.visual_followups.map(item => item.name)]);
  assert.ok(releaseWritten.every(([name, bytes]) => bytes.equals(sourceBytes.get(name))), 'Scoped release workdir must retain exact reviewed bytes');
  checked('supabase', ['migration', 'up', '--local', '--workdir', releaseWorkdir]);
  const releaseHistory = JSON.parse(sql(historyQuery));
  assert.deepEqual(releaseHistory.map(row => row.version), versionsOf(releasePlan.map(([name]) => name)));
  assert.deepEqual(releaseHistory.filter(row => row.version <= migrationVersion), releaseBaselineHistory);
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), followupReadiness);
  assert.equal(sql("select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname in ('card_provider_attempts','card_provider_private_events','card_payments_pilot_revisions','payment_terminals','card_attempt_identity_tombstones');"), '0',
    'The unrelated pending payment schema must remain absent');
  receipt.scoped_visual_release = { status: 'PASS', migration_versions: releaseHistory.map(row => row.version),
    pending_payment_omitted: followUpName, pending_payment_schema_absent: true,
    prior_history_unchanged: true, ready_for_real_service_lifecycle: true,
    schema_sha256: sha256(schemaSnapshot()), history_sha256: sha256(sql(historyQuery)) };
  const finalSources = await readMigrationSources(migrationsDirectory);
  assert.ok(finalSources.length === sources.length && finalSources.every(([name, bytes], index) =>
    name === sources[index][0] && bytes.equals(sources[index][1])), 'Every tracked migration source must remain byte-identical');
  receipt.tracked_migration_sources_unchanged = 'PASS';

  // BIZBOT-STOREFRONT-MOBILE-ORDERING-UX-002: extend only the exact visual stack
  // with the acknowledged theme; no payment, POS duty or G1 is applied here.
  phase = 'apply_reviewed_site_theme';
  assert.deepEqual(JSON.parse(sql(siteThemeReadinessQuery)), { content_v4: false, menu_v8: false },
    'The new site-theme readers must be absent before the separate theme phase');
  const beforeSiteThemeLegacyReaders = sql(legacyReadersQuery);
  const siteThemePlan = siteThemeReleaseSources(sources);
  await writeFile(join(releaseWorkdir, 'supabase/migrations', siteThemeSuccessor.name), sourceBytes.get(siteThemeSuccessor.name));
  const themeWritten = await readMigrationSources(join(releaseWorkdir, 'supabase/migrations'));
  assert.deepEqual(themeWritten.map(([name]) => name), siteThemePlan.map(([name]) => name),
    'The theme workdir must contain exactly the visual-release plan followed by site theme');
  assert.ok(themeWritten.every(([name, bytes]) => bytes.equals(sourceBytes.get(name))),
    'The theme workdir must retain exact reviewed bytes');
  checked('supabase', ['migration', 'up', '--local', '--workdir', releaseWorkdir]);
  const siteThemeVersion = siteThemeSuccessor.name.slice(0, 14);
  const siteThemeHistory = JSON.parse(sql(historyQuery));
  assert.deepEqual(siteThemeHistory.map(row => row.version), versionsOf(siteThemePlan.map(([name]) => name)),
    'The current lifecycle history must contain exactly the visual-release plan and site theme');
  assert.equal(siteThemeHistory.filter(row => row.version === siteThemeVersion).length, 1,
    'The site-theme migration must have exactly one history row');
  assert.deepEqual(siteThemeHistory.filter(row => row.version !== siteThemeVersion), releaseHistory,
    'Every history row preceding site theme must remain unchanged');
  const siteThemeReadiness = JSON.parse(sql(siteThemeReadinessQuery));
  assert.deepEqual(siteThemeReadiness, { content_v4: true, menu_v8: true }, 'The new current lifecycle readers must exist');
  const siteThemeGrants = JSON.parse(sql(siteThemeGrantsQuery));
  assert.deepEqual(siteThemeGrants, { content_v4_authenticated: true, menu_v8_anon: true, menu_v8_authenticated: true },
    'The current lifecycle readers must retain their reviewed EXECUTE grants');
  assert.deepEqual(JSON.parse(sql(followupReadinessQuery)), followupReadiness,
    'Every reviewed visual follow-up must remain ready after site theme');
  assert.equal(sql("select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname in ('card_provider_attempts','card_provider_private_events','card_payments_pilot_revisions','payment_terminals','card_attempt_identity_tombstones');"), '0',
    'The unrelated pending payment schema must remain absent after site theme');
  const afterSiteThemeLegacyReaders = sql(legacyReadersQuery);
  assert.equal(afterSiteThemeLegacyReaders, beforeSiteThemeLegacyReaders,
    'All six legacy reader definitions, ACLs and owners must remain byte-identical across site theme');
  receipt.site_theme_release = { status: 'PASS', applied_version: siteThemeVersion,
    migration_versions: siteThemeHistory.map(row => row.version), prior_history_unchanged: true,
    legacy_readers_before_sha256: sha256(beforeSiteThemeLegacyReaders), legacy_readers_after_sha256: sha256(afterSiteThemeLegacyReaders),
    followup_readiness_unchanged: true, pending_payment_schema_absent: true,
    readiness: siteThemeReadiness, grants: siteThemeGrants,
    schema_sha256: sha256(schemaSnapshot()), history_sha256: sha256(sql(historyQuery)),
    ready_for_real_service_lifecycle: true, lifecycle_stack: 'post_site_theme_release',
    scoped_visual_release_describes: 'historical_pre_site_theme_stack' };
  const finalSiteThemeSources = await readMigrationSources(migrationsDirectory);
  assert.ok(finalSiteThemeSources.length === sources.length && finalSiteThemeSources.every(([name, bytes], index) =>
    name === sources[index][0] && bytes.equals(sources[index][1])), 'Every tracked migration source must remain byte-identical');
  receipt.status = 'PASS';
  phase = 'complete';
} catch (error) {
  // Fixed assertions only; never persist a command's environment or full output.
  receipt.failure = String(error.message).split('\n')[0];
  process.exitCode = 1;
} finally {
  receipt.phase = phase;
  await writeFile(join(artifactDir, 'migration-atomicity.json'), JSON.stringify(receipt, null, 2) + '\n', { mode: 0o600 });
  for (const workdir of temporaries) await rm(workdir, { recursive: true, force: true });
  console.log(JSON.stringify(receipt));
}
