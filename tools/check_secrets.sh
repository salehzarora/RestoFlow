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
# Exit code 0 = clean, 1 = potential leak found. This IS enforced in CI as a
# guardrail step (.github/workflows/ci.yml — DECISION D-011).
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
  # Match env files by ANY prefix, not just the ".env"-leading dotfile forms, so
  # a non-dotfile secret env file (e.g. supabasekey.env.local) is blocked by name
  # even if a .gitignore gap let it slip past --exclude-standard (RF-LIVE-001).
  case "$base" in
    .env|.env.*|*.env|*.env.local)
      echo "BLOCK  un-ignored env file (may hold secrets): $f"; fail=1 ;;
  esac
  case "$f" in
    *.pem|*.key|*.p12|*.pfx|*.keystore|*.jks|*service_role*|*service-role* \
    |*credentials*.json|google-services.json|GoogleService-Info.plist \
    |signing_keys.json|*/signing_keys.json \
    |.mcp.json|*/.mcp.json)
      echo "BLOCK  un-ignored secret-bearing file: $f"; fail=1 ;;
  esac
  # RELEASE-KEY-AND-PIPELINE-001: an Android signing-properties file holds the
  # keystore AND key passwords in plain text. It must live outside the repo.
  # `*.example` already returned above, so the placeholder template is allowed.
  case "$base" in
    key.properties|signing.properties|release-signing.properties|*-signing.properties)
      echo "BLOCK  un-ignored Android signing-properties file: $f"; fail=1 ;;
  esac
done < <(scan_list)

# ---- 1b) Android signing credentials inside file CONTENTS -----------------
# A committed storePassword/keyPassword is a fleet-level compromise: it unlocks
# the key that owns every installed RestoFlow app.
#
# Only a LITERAL value is a finding. Two things are deliberately NOT findings,
# because flagging them would train people to ignore this guard:
#   * CODE that reads the value at build time
#     (`storePassword = props.getProperty("storePassword")`), and
#   * obvious placeholders in templates and documentation (`<CHANGE_ME>`).
SIGNING_KEYS='(storePassword|keyPassword)'
SIGNING_PLACEHOLDER='=[[:space:]]*("?)(<[^>]*>|\{\{[^}]*\}\}|CHANGE_?ME|REPLACE_?ME|YOUR_[A-Za-z_]*|EXAMPLE[A-Za-z_]*|PLACEHOLDER|TODO|\.\.\.|xxx+)'
# RHS that is an expression/lookup rather than a secret literal.
SIGNING_CODE='getProperty|System\.|getenv|\$\{|\$env:|env\(|props|properties\[|Get-Content|Matches|\bparam\b|=[[:space:]]*[$"'"'"']?\$'
SIGNING_EXEMPT='tools/test_check_secrets_signing.sh'  # holds this guard's own fixtures
# ONE batched grep, not one per file. Spawning three greps per file cost ~5
# minutes on this repo under Windows; `xargs` keeps it to a handful of
# processes. -I skips binaries, -H forces the filename prefix even when a batch
# happens to contain a single file.
signing_hits="$(scan_list \
  | xargs -0 grep -IHnEi "${SIGNING_KEYS}[[:space:]]*=" 2>/dev/null \
  | grep -vE "^($SELF|$SIGNING_EXEMPT|[^:]*\.example):" \
  | grep -vEi "$SIGNING_PLACEHOLDER" \
  | grep -vEi "$SIGNING_CODE")"
if [ -n "$signing_hits" ]; then
  printf '%s\n' "$signing_hits" | cut -d: -f1,2 | sort -u | while IFS=: read -r sf sl; do
    echo "BLOCK  Android signing password in $sf at line $sl (value redacted)"
  done
  fail=1
fi

# ---- 2) credential value patterns inside contents -------------------------
# Batched deliberately. This used to spawn two greps PER FILE, which on Windows
# cost ~5 minutes for ~1800 files and made the guard the slowest step in CI;
# `xargs` does the same work in about a second. Same regex, same file set, same
# output - only the process count changed. -I skips binaries (replacing the old
# per-file `grep -Iq .` probe) and -H forces the filename prefix.
value_hits="$(scan_list \
  | xargs -0 grep -IHnE "$VALUE_PATTERNS" 2>/dev/null \
  | grep -vE "^$SELF:")"
if [ -n "$value_hits" ]; then
  printf '%s\n' "$value_hits" | cut -d: -f1,2 | sort -t: -k1,1 -k2,2n -u | awk -F: '
    { lines[$1] = (lines[$1] == "" ? $2 : lines[$1] "," $2) }
    END { for (f in lines)
            printf "BLOCK  possible credential value in %s at line(s): %s (value redacted)\n", f, lines[f] }'
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "FAIL: potential secret(s) detected. Remove/ignore them before committing."
  echo "      If a real secret was already committed, treat it as compromised:"
  echo "      rotate it and purge it from history (see docs/OPERATIONS_AND_RECOVERY.md)."
  exit 1
fi

echo "OK: no committable secrets detected (scanned tracked + non-ignored files)."
exit 0
