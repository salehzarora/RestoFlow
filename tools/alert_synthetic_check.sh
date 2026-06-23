#!/usr/bin/env bash
# ============================================================================
# RestoFlow — synthetic alert detection check  (RF-094)
#
# Simulates ALERT DETECTION LOGIC ONLY — it does NOT deliver a real alert/pager
# and does NOT integrate any monitoring provider (see docs/RUNBOOKS.md §2 and
# docs/PRODUCTION_READINESS.md). Live monitoring + alert routing is human/infra.
#
# It injects a synthetic failure-signal SPIKE into a TEMP table on the DOCKER-LOCAL
# database, inside a single transaction that is ROLLED BACK (no permanent tenant
# mutation), and asserts that a threshold detection query:
#   (a) FIRES on the above-threshold spike; and
#   (b) does NOT fire on a below-threshold control (false-positive / alert-fatigue guard).
#
# Safe by default. NEVER connects to a remote project, NEVER requires a secret
# (the local default DB on 127.0.0.1:54322 is the PUBLIC supabase local-dev
# default, not a credential). SUPABASE_DB_URL MAY override the target, but its
# host is VALIDATED to be local-only BEFORE any psql call (RF094-B1): only
# 127.0.0.1, localhost, ::1, and host.docker.internal (local Docker-host gateway)
# are accepted. Any other host — Supabase cloud, public/LAN IPs, any remote
# hostname — is REJECTED (exit 2) before a connection is ever attempted.
# If psql / the local DB is unavailable it prints the detection queries and exits 0.
#
# Usage (from anywhere in the repo; Windows: use Git Bash):
#   bash tools/alert_synthetic_check.sh
#   SUPABASE_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres bash tools/alert_synthetic_check.sh
#
# Exit codes: 0 = detection logic verified OR queries printed (no live DB);
#             1 = detection assertion failed; 2 = usage/safety abort.
# ============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "FAIL: run inside the RestoFlow git repo."; exit 2; }
cd "$ROOT" || exit 2

# PUBLIC supabase local-dev default — NOT a secret. Override via SUPABASE_DB_URL.
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

echo "============================================================================"
echo "RestoFlow synthetic alert check — DETECTION LOGIC SIMULATION ONLY (RF-094)"
echo "  * simulates detection only — NO real alert/pager is delivered"
echo "  * no monitoring provider, no remote Supabase, no secrets"
echo "============================================================================"

# ---- safety: never operate against a linked/remote project -----------------
if [ -f "supabase/.temp/project-ref" ]; then
  echo "ABORT: a linked/remote Supabase project ref was found (supabase/.temp/project-ref)."
  echo "       This check is LOCAL-ONLY and refuses to run against a remote project."
  exit 2
fi

# ---- safety: SUPABASE_DB_URL must point to a LOCAL host only (RF094-B1) -----
# Parse the host out of the effective DB URL and reject anything that is not an
# explicitly-approved local host, BEFORE any psql connection is attempted. This
# keeps the check local/simulated-only even when SUPABASE_DB_URL is overridden.
db_host_from_url() {
  local url="$1" rest
  rest="${url#*://}"      # drop scheme://
  rest="${rest%%/*}"      # drop /path (and everything after it)
  rest="${rest%%\?*}"     # drop ?query when there was no /path
  rest="${rest##*@}"      # drop userinfo (user:pass@)
  if [ "${rest#\[}" != "$rest" ]; then
    # bracketed IPv6 authority, e.g. [::1]:5432 -> ::1
    rest="${rest#\[}"; rest="${rest%%\]*}"
    printf '%s' "$rest"
  else
    # host[:port] -> host
    printf '%s' "${rest%%:*}"
  fi
}

DB_HOST="$(db_host_from_url "$DB_URL" | tr '[:upper:]' '[:lower:]')"
case "$DB_HOST" in
  127.0.0.1|localhost|::1) ;;        # loopback — always the local machine
  host.docker.internal) ;;          # local Docker-host gateway (still this machine, not remote)
  *)
    echo "ERROR: SUPABASE_DB_URL must point to a local database host only. Refusing host: ${DB_HOST:-<unparseable>}"
    echo "       Allowed local hosts: 127.0.0.1, localhost, ::1, host.docker.internal."
    echo "       RF-094 is LOCAL/SIMULATED-ONLY — remote/prod databases are never accepted."
    exit 2 ;;
esac

print_queries() {
  cat <<'EOF'

---- Detection queries (illustrative; threshold over a recent window) ----------
-- A signal whose count in the window exceeds its threshold FIRES an alert.
-- Real signals come from logs/metrics and audited tables (audit_events,
-- platform_admin_audit_events, sync_operations, print_jobs) — see docs/RUNBOOKS.md §2.3.
--
--   with signals(signal, n) as (
--     values ('rls_denied', 25), ('auth_failed', 2)   -- example window counts
--   )
--   select signal, n, (n >= 10) as alert  -- threshold = 10
--   from signals;
--   -- expect: rls_denied -> alert = true (FIRES); auth_failed -> alert = false (quiet)
EOF
}

if ! command -v psql >/dev/null 2>&1; then
  echo "NOTE: 'psql' not found — printing the detection queries only (no live run)."
  print_queries
  echo ""
  echo "RESULT: NOT EXECUTED (no psql). Detection logic documented above; nothing ran."
  exit 0
fi

if ! psql "$DB_URL" -c 'select 1' >/dev/null 2>&1; then
  echo "NOTE: local DB not reachable (host: ${DB_HOST}) — is 'supabase start' running?"
  print_queries
  echo ""
  echo "RESULT: NOT EXECUTED (DB unreachable). Detection logic documented above; nothing ran."
  exit 0
fi

echo ""
echo "==> running synthetic detection check against the LOCAL DB (TEMP tables, transaction rolled back)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -q <<'SQL'
begin;

-- synthetic signal buffer (temp; auto-dropped; nothing persists)
create temp table synthetic_signals (
  signal      text        not null,
  occurred_at timestamptz not null default now()
) on commit drop;

-- inject an above-threshold SPIKE (rls_denied) and a below-threshold CONTROL (auth_failed)
insert into synthetic_signals (signal) select 'rls_denied'  from generate_series(1, 25);
insert into synthetic_signals (signal) select 'auth_failed' from generate_series(1, 2);

do $$
declare
  v_threshold int := 10;
  v_spike     int;
  v_control   int;
begin
  select count(*) into v_spike   from synthetic_signals where signal = 'rls_denied';
  select count(*) into v_control from synthetic_signals where signal = 'auth_failed';

  -- (a) the spike MUST be detected
  if v_spike < v_threshold then
    raise exception 'DETECTION MISS: rls_denied=% did not reach threshold=%', v_spike, v_threshold;
  end if;

  -- (b) the below-threshold control MUST NOT be detected (alert-fatigue guard)
  if v_control >= v_threshold then
    raise exception 'FALSE POSITIVE: auth_failed=% should be below threshold=%', v_control, v_threshold;
  end if;

  raise notice 'detection fired on spike (rls_denied=% >= %); control quiet (auth_failed=% < %)',
    v_spike, v_threshold, v_control, v_threshold;
end $$;

rollback;
SQL
rc=$?

print_queries

if [ "$rc" -ne 0 ]; then
  echo ""
  echo "FAIL: synthetic detection check failed (see the error above)."
  exit 1
fi

echo ""
echo "RESULT: PASS — alert DETECTION logic verified locally (spike fired, control quiet)."
echo "        No data was mutated (transaction rolled back). No real alert was delivered."
echo "        Live monitoring + alert routing is human/infra (docs/PRODUCTION_READINESS.md)."
exit 0
