// RF-112 local browser smoke — safety guards.
//
// Two invariants protect the supervised local demo:
//   1. LOCAL-ONLY: the smoke suite must never point a browser at a remote /
//      production origin. It drives real URLs and could exercise onboarding in
//      later steps, so it is fenced to localhost.
//   2. NO SERVICE-ROLE CREDENTIALS (DECISION D-011): a service-role key bypasses
//      PostgreSQL RLS entirely (RISK R-003, CRITICAL). Clients and tests use only
//      the PUBLIC anon/publishable key. This guard aborts the whole run if the
//      environment carries anything that looks like a service-role/secret key.
//
// Neither guard ever prints a secret value — only the offending variable NAME.

const LOCAL_HOSTS: ReadonlySet<string> = new Set([
  'localhost',
  '127.0.0.1',
  '::1',
  '0.0.0.0',
]);

/** Throw unless `url` targets a local origin (localhost / loopback / *.localhost). */
export function assertLocalOnly(url: string): void {
  let host: string;
  try {
    host = new URL(url).hostname;
  } catch {
    throw new Error(`RF-112 smoke: not a valid URL: "${url}".`);
  }
  // URL.hostname strips the brackets from IPv6 already; normalise just in case.
  const normalized = host.replace(/^\[|\]$/g, '').toLowerCase();
  const isLocal =
    LOCAL_HOSTS.has(normalized) || normalized.endsWith('.localhost');
  if (!isLocal) {
    throw new Error(
      `RF-112 smoke is LOCAL-ONLY and refuses to run against non-local host ` +
        `"${host}" (${url}). Point RF_E2E_*_URL at a localhost origin.`,
    );
  }
}

// A service-role / secret credential looks like one of these. Deliberately
// specific so the PUBLIC anon key (sb_publishable_...) never matches.
const SECRET_NAME_OR_VALUE = /service[_-]?role/i; // legacy label, name or value
const SECRET_KEY_PREFIX = /\bsb_secret_[A-Za-z0-9]/; // new-format Supabase secret

// A JWT whose decoded payload declares "role":"service_role" (legacy Supabase
// service key). Matched structurally, then decoded — we never log the token.
const JWT = /eyJ[A-Za-z0-9_-]{6,}\.([A-Za-z0-9_-]{6,})\.[A-Za-z0-9_-]{6,}/;

function isServiceRoleJwt(value: string): boolean {
  const match = value.match(JWT);
  if (!match) return false;
  try {
    const b64 = match[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload = Buffer.from(b64, 'base64').toString('utf8');
    return /"role"\s*:\s*"service_role"/.test(payload);
  } catch {
    return false;
  }
}

/**
 * Abort the run if any environment variable looks like a service-role/secret key.
 * Returns the list of offending variable NAMES (never values) for tests to assert
 * against; throws when non-empty so a misconfigured shell fails fast and loud.
 */
export function findServiceRoleEnv(
  env: NodeJS.ProcessEnv = process.env,
): string[] {
  const offenders: string[] = [];
  for (const [name, value] of Object.entries(env)) {
    if (!value) continue;
    const suspicious =
      SECRET_NAME_OR_VALUE.test(name) ||
      SECRET_NAME_OR_VALUE.test(value) ||
      SECRET_KEY_PREFIX.test(value) ||
      isServiceRoleJwt(value);
    if (suspicious) offenders.push(name);
  }
  return offenders;
}

/** Throw if the environment carries a service-role/secret-looking credential. */
export function assertNoServiceRoleKey(
  env: NodeJS.ProcessEnv = process.env,
): void {
  const offenders = findServiceRoleEnv(env);
  if (offenders.length > 0) {
    throw new Error(
      `RF-112 smoke refuses to run: environment variable(s) ` +
        `[${offenders.join(', ')}] look like a service-role/secret credential. ` +
        `Use ONLY the public anon/publishable key (DECISION D-011; RISK R-003). ` +
        `(Values are never printed.)`,
    );
  }
}
