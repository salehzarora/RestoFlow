import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

// This runner has no production credentials. Production-looking source URLs
// are compared by injected adapters only; the sole network fetch is loopback.
const DATABASE_CONTAINER = 'bizbot_platform353_pg_20261020';
const NETWORK = 'bizbot_platform353_net_20261020';
const REST_IMAGE = 'public.ecr.aws/supabase/postgrest:v14.13';
const SYNTHETIC_DB_PASSWORD = 'synthetic-platform353-local-only';
const JWT_SECRET = 'synthetic-platform353-local-only-jwt-secret-never-production-000000';
const q = (value) => `'${String(value).replaceAll("'", "''")}'`;
function processOutput(command, args, input, maxBytes = 64 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    const chunks = []; const errors = []; let size = 0;
    const timer = setTimeout(() => child.kill(), 120_000);
    child.stdout.on('data', (b) => { size += b.length; if (size > maxBytes) child.kill(); else chunks.push(b); });
    child.stderr.on('data', (b) => { if (errors.reduce((n, x) => n + x.length, 0) < 4096) errors.push(b); });
    child.stdin.on('error', () => { /* Process exit is classified below; never print a pipe error. */ });
    child.on('error', () => { clearTimeout(timer); reject(new Error('local_process_start_failed')); });
    child.on('exit', (code) => {
      clearTimeout(timer);
      if (code === 0 && size <= maxBytes) resolve(Buffer.concat(chunks).toString('utf8'));
      else reject(Object.assign(new Error('local_process_failed'), { localCode: code, localStderr: Buffer.concat(errors).toString('utf8') }));
    });
    child.stdin.end(input);
  });
}
const docker = (args, input) => processOutput('docker', args, input);
const report = { status: 'BLOCKED', evidenceKind: 'local_real_handlers_http_rpc_database_with_synthetic_transport',
  startedUtc: new Date().toISOString(), checks: [], productionConnections: 0, physicalPrints: 0, actualFcmSends: 0 };
const passed = (name, facts = {}) => report.checks.push({ name, result: 'PASS', ...facts });

if (process.env.BIZBOT_PLATFORM353_LOCAL_ACCEPTANCE !== 'LOCAL_SYNTHETIC_ONLY' || process.argv[2] !== '--run') {
  console.log(JSON.stringify({ status: 'NOT_RUN', reason: 'explicit_local_synthetic_opt_in_required' }));
} else {
  const suffix = randomUUID().replaceAll('-', '').slice(0, 12);
  const database = `platform353_e2e_${suffix}`;
  const restContainer = `bizbot_platform353_rest_${suffix}`;
  let restStarted = false;
  const sql = async (source) => (await docker(['exec', '-i', DATABASE_CONTAINER, 'psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', '-U', 'supabase_admin', '-d', database], source)).trim();
  try {
    assert.match(database, /^platform353_e2e_[0-9a-f]{12}$/);
    const metadata = JSON.parse(await docker(['inspect', DATABASE_CONTAINER]));
    assert.equal(metadata.length, 1);
    assert.equal(metadata[0].Name, `/${DATABASE_CONTAINER}`);
    assert.equal(metadata[0].Config.Image, 'public.ecr.aws/supabase/postgres:17.6.1.143');
    assert.equal(metadata[0].HostConfig.PortBindings['5432/tcp'][0].HostIp, '127.0.0.1');
    assert.equal(metadata[0].HostConfig.PortBindings['5432/tcp'][0].HostPort, '55483');
    assert.deepEqual(Object.keys(metadata[0].NetworkSettings.Networks), [NETWORK]);
    assert.equal((await docker(['network', 'inspect', NETWORK, '--format', '{{.Internal}}'])).trim(), 'true');
    await docker(['image', 'inspect', REST_IMAGE, '--format', '{{.Id}}']);
    const existing = (await docker(['exec', DATABASE_CONTAINER, 'psql', '-X', '-A', '-t', '-U', 'postgres', '-d', 'postgres', '-c', `select exists(select 1 from pg_database where datname=${q(database)})`])).trim();
    assert.equal(existing, 'f');
    // Read-only dump of the task-owned migrated fixture, then a NEW database.
    const dump = await docker(['exec', DATABASE_CONTAINER, 'pg_dump', '-U', 'supabase_admin', 'postgres']);
    await docker(['exec', DATABASE_CONTAINER, 'createdb', '-U', 'supabase_admin', '-O', 'postgres', database]);
    await sql(dump);
    await sql(await readFile(new URL('./fixture.sql', import.meta.url), 'utf8'));
    passed('disposable_loopback_fixture_isolated', { database, networkInternal: true, fixturePort: 55483 });
    await docker(['run', '-d', '--name', restContainer, '--label', 'bizbot.work-id=BIZBOT-PLATFORM-ONLINE-ORDERS-353',
      '--network', 'container:' + DATABASE_CONTAINER,
      '-e', 'PGRST_DB_URI=postgres://postgres:' + SYNTHETIC_DB_PASSWORD + '@127.0.0.1:5432/' + database,
      '-e', 'PGRST_DB_SCHEMAS=public', '-e', 'PGRST_DB_ANON_ROLE=anon', '-e', 'PGRST_JWT_SECRET=' + JWT_SECRET,
      '-e', 'PGRST_SERVER_HOST=127.0.0.1', REST_IMAGE]);
    restStarted = true;
    const root = fileURLToPath(new URL('../../', import.meta.url));
    const output = await docker(['run', '--rm', '--network', 'container:' + DATABASE_CONTAINER,
      '--mount', 'type=bind,source=' + root + ',target=/workspace,readonly', '-w', '/workspace',
      '-e', 'BIZBOT_SYNTHETIC_DATABASE=' + database, 'node:24-bookworm-slim',
      'node', 'tools/platform_online_orders_353/acceptance-http.mjs']);
    const inner = JSON.parse(output);
    report.checks.push(...inner.checks);
    Object.assign(report, { ...inner, checks: report.checks });
    if (report.status !== 'PASS') process.exitCode = 1;
  } catch (error) {
    report.failure = { name: error.name, category: error.message, ...(Number.isInteger(error.localCode) ? { localProcessExit: error.localCode } : {}) };
    // A useful local diagnostic is a fixed PostgreSQL error code, never raw SQL
    // or connection output. All fixture credentials are synthetic regardless.
    const code = /(?:ERROR|FATAL):\s+([0-9A-Z]{5})/.exec(error.localStderr ?? '')?.[1];
    if (code) report.failure.fixedLocalError = code;
    process.exitCode = 1;
  } finally {
    if (restStarted) await docker(['rm', '-f', restContainer]).catch(() => {});
    report.finishedUtc = new Date().toISOString();
    console.log(JSON.stringify(report, null, 2));
  }
}
