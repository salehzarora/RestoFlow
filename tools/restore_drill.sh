#!/usr/bin/env bash
# ============================================================================
# RestoFlow — LOCAL-ONLY restore drill  (RF-094)
#
# Rehearses the BACKUP/RESTORE PROCEDURE against the DOCKER-LOCAL Supabase stack
# only. It is a SIMULATION of the restore *procedure* + post-restore validation,
# NOT a real production PITR drill (see docs/RUNBOOKS.md §1 and
# docs/PRODUCTION_READINESS.md). A REAL restore drill against production backups
# is human/infra work and is NOT performed by this script.
#
# Safe by default. This script NEVER:
#   * connects to a remote Supabase project, runs `supabase link`, or `db push`;
#   * resets / drops / truncates production; it operates on the LOCAL stack only;
#   * requires or reads any secret (the local default DB on 127.0.0.1:54322 is the
#     PUBLIC supabase local-dev default, not a credential).
#
# What it does (default `run` mode):
#   1) refuses to run if a linked/remote project ref is present (defence in depth);
#   2) if the local stack is up: `supabase db reset` (replay migrations — the local
#      "up applies cleanly" gate) then `supabase test db` (canonical isolation suite,
#      incl. supabase/tests/rf019_tenant_isolation_harness_test.sql);
#   3) prints the post-restore validation checklist + reference validation queries.
#   If the CLI/Docker/local stack are unavailable it prints the procedure and exits
#   0 (nothing unsafe ran). Real command failures (reset/test) exit non-zero.
#
# Usage (from anywhere in the repo; Windows: use Git Bash):
#   bash tools/restore_drill.sh            # run the local drill if the stack is up
#   bash tools/restore_drill.sh --check    # print prereqs + checklist only (no run)
#   bash tools/restore_drill.sh --help
#
# Exit codes: 0 = drill ran clean OR procedure printed (no run);
#             1 = a local drill command failed; 2 = usage/safety abort.
# ============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "FAIL: run inside the RestoFlow git repo."; exit 2; }
cd "$ROOT" || exit 2

MODE="run"
case "${1:-}" in
  --check|-c) MODE="check" ;;
  --help|-h)
    echo "Usage: bash tools/restore_drill.sh [--check]"
    echo "  (no args)  run the LOCAL restore drill if the local Supabase stack is up"
    echo "  --check    print prerequisites + restore-validation checklist only (no run)"
    exit 0 ;;
  "") ;;
  *) echo "FAIL: unknown argument '$1' (try --help)."; exit 2 ;;
esac

echo "============================================================================"
echo "RestoFlow restore drill — LOCAL-ONLY SIMULATION (RF-094)"
echo "  * NOT a real production PITR drill (that is human/infra; see RUNBOOKS.md §1)"
echo "  * no remote Supabase, no link, no db push, no secrets"
echo "============================================================================"

# ---- safety: never operate against a linked/remote project -----------------
if [ -f "supabase/.temp/project-ref" ]; then
  echo "ABORT: a linked/remote Supabase project ref was found (supabase/.temp/project-ref)."
  echo "       This drill is LOCAL-ONLY and refuses to run against a remote project."
  exit 2
fi

print_checklist() {
  cat <<'EOF'

---- Post-restore validation checklist (run after ANY restore) -------------
Restore to a NEW/ISOLATED instance first — never overwrite live prod blindly.
  [ ] Row counts per organization_id match the expected snapshot; no tenant's
      rows appear under another tenant's id (no cross-tenant resurrection, R-003).
  [ ] RLS enabled AND forced on every tenant-scoped table; no-context query → 0 rows.
  [ ] Isolation suite green (supabase test db): T-001 cross-org read, T-003 KDS/
      kitchen cannot read financials, T-004 revoked device, T-007..T-010 platform plane.
  [ ] Money intact as integer _minor (D-007) — no float types on *_minor columns.
  [ ] Receipt-sequence integrity (D-021): per-branch monotonic sequences do not
      regress or duplicate; verify the latest assigned value per branch.
  [ ] Sync reconciliation safe (D-022): idempotency (device_id, local_operation_id)
      + server inbox/ledger prevent duplicate application after restore.
  [ ] No revived revoked access (R-007): revoked devices/employees stay revoked.

NEVER reset/drop/truncate production. NEVER copy real tenant data into local/dev/
staging. The local drill uses synthetic data only. (docs/OPERATIONS_AND_RECOVERY.md
§4.4/§5/§2.1; docs/RUNBOOKS.md §1.)
EOF
}

print_validation_queries() {
  cat <<'EOF'

---- Reference validation queries (illustrative; run against the restored DB) ----
-- RLS must be enabled AND forced on every tenant-scoped table:
--   select n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity
--   from pg_class c join pg_namespace n on n.oid = c.relnamespace
--   where n.nspname = 'public' and c.relkind = 'r'
--   order by c.relrowsecurity, c.relname;   -- expect rowsecurity = true (and forced where required)
--
-- No floating-point money: every *_minor column must be an integer type (D-007):
--   select table_name, column_name, data_type
--   from information_schema.columns
--   where column_name like '%\_minor' escape '\'
--     and data_type not in ('bigint','integer','smallint');   -- expect ZERO rows
--
-- Row counts per tenant (template — substitute a tenant-scoped table):
--   select organization_id, count(*) from public.<tenant_table> group by 1 order by 1;
EOF
}

# ---- check mode: print only -------------------------------------------------
if [ "$MODE" = "check" ]; then
  echo ""
  echo "[--check] Prerequisites for the LOCAL drill:"
  command -v supabase >/dev/null 2>&1 && echo "  ok  supabase CLI found" || echo "  --  supabase CLI NOT found (needed to execute the drill)"
  command -v docker   >/dev/null 2>&1 && echo "  ok  docker found"        || echo "  --  docker NOT found (needed for the local stack)"
  print_checklist
  print_validation_queries
  echo ""
  echo "[--check] Printed the procedure only — nothing was executed."
  exit 0
fi

# ---- run mode: execute the local drill if the stack is available ------------
if ! command -v supabase >/dev/null 2>&1; then
  echo "NOTE: 'supabase' CLI not found — cannot execute the local drill."
  echo "      Install the Supabase CLI, or run: bash tools/restore_drill.sh --check"
  print_checklist
  echo ""
  echo "RESULT: NOT EXECUTED (no CLI). Procedure printed above; nothing unsafe ran."
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "NOTE: Docker does not appear to be running — the local Supabase stack needs it."
  echo "      Start Docker Desktop, then: supabase start"
  print_checklist
  echo ""
  echo "RESULT: NOT EXECUTED (no Docker). Procedure printed above; nothing unsafe ran."
  exit 0
fi

if ! supabase status >/dev/null 2>&1; then
  echo "NOTE: the local Supabase stack is not running. Start it first with: supabase start"
  print_checklist
  echo ""
  echo "RESULT: NOT EXECUTED (stack down). Procedure printed above; nothing unsafe ran."
  exit 0
fi

echo ""
echo "==> [1/2] supabase db reset  (replay migrations on the LOCAL stack — 'up applies cleanly')"
if ! supabase db reset; then
  echo "FAIL: 'supabase db reset' failed on the local stack."
  exit 1
fi

echo ""
echo "==> [2/2] supabase test db  (canonical tenant-isolation suite)"
if ! supabase test db; then
  echo "FAIL: 'supabase test db' failed — a restore that re-opens isolation gaps is NOT complete (R-003)."
  exit 1
fi

print_checklist
print_validation_queries
echo ""
echo "RESULT: LOCAL DRILL EXECUTED CLEAN — migrations replayed + isolation suite green."
echo "        A REAL restore drill against production backups is human/infra"
echo "        (docs/RUNBOOKS.md §1.1). Go-live remains BLOCKED (docs/PRODUCTION_READINESS.md)."
exit 0
