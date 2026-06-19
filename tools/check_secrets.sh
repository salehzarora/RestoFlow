#!/usr/bin/env bash
# ============================================================================
# RestoFlow — local secret-leak scan  (RF-013)
#
# Purpose: a fast, dependency-free guard that fails if a real secret could be
# committed. It scans files that COULD enter git (tracked + untracked, but NOT
# gitignored — `--exclude-standard`), so a properly ignored `.env.local` is
# never a finding, while an un-ignored secret IS.
#
# It checks two things:
#   1) Forbidden secret-bearing FILENAMES that are not gitignored
#      (.env, *.pem, *.key, *service_role*, signing_keys.json, ...).
#   2) Credential VALUE patterns inside file CONTENTS (JWTs, sb_secret_ keys,
#      AWS / Google keys, PEM private keys, Slack tokens).
#
# It NEVER prints a matched secret value — only "<file>:<line>" locations.
# Exit code 0 = clean, 1 = potential leak found. Wire into CI in a later ticket.
#
# Run from anywhere in the repo:   bash tools/check_secrets.sh
# (Windows: use Git Bash.)
# ============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 2
SELF="tools/check_secrets.sh"
fail=0

# Credential VALUE patterns. Deliberately specific so placeholders such as
# "<...>", "sb_secret_*" or "env(SERVICE_KEY)" do NOT match — only real values.
VALUE_PATTERNS='eyJ[A-Za-z0-9_=-]{10,}\.eyJ[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_=-]{10,}'
VALUE_PATTERNS+='|sb_secret_[A-Za-z0-9]{16,}'
VALUE_PATTERNS+='|sbp_[A-Za-z0-9]{20,}'
VALUE_PATTERNS+='|AKIA[0-9A-Z]{16}'
VALUE_PATTERNS+='|AIza[0-9A-Za-z_-]{35}'
VALUE_PATTERNS+='|-----BEGIN [A-Z ]*PRIVATE KEY-----'
VALUE_PATTERNS+='|xox[baprs]-[A-Za-z0-9-]{10,}'

scan_list() { git ls-files --cached --others --exclude-standard -z; }

# ---- 1) forbidden filenames that are NOT gitignored ------------------------
while IFS= read -r -d '' f; do
  case "$f" in
    *.example) continue ;;   # placeholder templates are allowed
  esac
  base="$(basename "$f")"
  case "$base" in
    .env|.env.*)
      echo "BLOCK  un-ignored env file (may hold secrets): $f"; fail=1 ;;
  esac
  case "$f" in
    *.pem|*.key|*.p12|*.pfx|*.keystore|*.jks|*service_role*|*service-role* \
    |*credentials*.json|google-services.json|GoogleService-Info.plist \
    |signing_keys.json|*/signing_keys.json)
      echo "BLOCK  un-ignored secret-bearing file: $f"; fail=1 ;;
  esac
done < <(scan_list)

# ---- 2) credential value patterns inside contents -------------------------
while IFS= read -r -d '' f; do
  [ "$f" = "$SELF" ] && continue          # don't scan this scanner's own regexes
  grep -Iq . "$f" 2>/dev/null || continue # skip binary / empty
  lines="$(grep -nE "$VALUE_PATTERNS" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ',' )"
  if [ -n "$lines" ]; then
    echo "BLOCK  possible credential value in $f at line(s): ${lines%,} (value redacted)"
    fail=1
  fi
done < <(scan_list)

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "FAIL: potential secret(s) detected. Remove/ignore them before committing."
  echo "      If a real secret was already committed, treat it as compromised:"
  echo "      rotate it and purge it from history (see docs/OPERATIONS_AND_RECOVERY.md)."
  exit 1
fi

echo "OK: no committable secrets detected (scanned tracked + non-ignored files)."
exit 0
