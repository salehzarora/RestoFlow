#!/usr/bin/env bash
# ============================================================================
# RestoFlow - no-hardcoded-user-facing-strings guard  (RF-020, DECISION D-014)
#
# Scaffolded app shells must render user-facing text via AppLocalizations
# (packages/l10n), never as literals. This guard flags the obvious cases in the
# SCAFFOLDED APP SHELLS ONLY (apps/*/lib/**/*.dart):
#       Text('literal')      Text("literal")
#       title: 'literal'     title: Text('literal')   (the inner Text(' matches)
# It is deliberately NARROW and low-noise: it does NOT scan packages/, tests,
# generated code, or ARB files, and it only looks at `Text(<quote>` and
# `title:<quote>` (lowercase `title:`, so `onGenerateTitle:` never matches).
#
# Allowed (NOT flagged): localization lookups like `Text(l10n.posAppTitle)` /
# `AppLocalizations.of(context)`, imports, package names, identifiers, and
# `debugShowCheckedModeBanner: false`.
#
# Location-only output; never prints code. Exit codes:
#   0 = clean   1 = violation found   2 = the guard's own self-test failed
# Run:  bash tools/check_no_hardcoded_strings.sh   (Windows: Git Bash)
# ============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 2
SELF="tools/check_no_hardcoded_strings.sh"

# Branch A: a Text() whose first argument is a string literal -> Text('  / Text("
# Branch B: a lowercase `title:` immediately assigned a string literal.
PATTERN="Text\([[:space:]]*[\"']|title:[[:space:]]*[\"']"

# ---- self-test: guard MUST catch real violations and MUST NOT flag clean -----
selftest() {
  local rc=0 s
  local must_match=(
    "Text('Hello')"
    'Text("Hello")'
    "title: 'My App'"
    "title: Text('literal')"
  )
  local must_not=(
    'Text(l10n.posAppTitle)'
    "import 'package:flutter/material.dart';"
    'AppLocalizations.of(context)'
    'debugShowCheckedModeBanner: false'
    'onGenerateTitle: (context) => AppLocalizations.of(context).posAppTitle'
  )
  for s in "${must_match[@]}"; do
    printf '%s\n' "$s" | grep -qE "$PATTERN" || { echo "SELFTEST FAIL: missed violation: [$s]"; rc=2; }
  done
  for s in "${must_not[@]}"; do
    if printf '%s\n' "$s" | grep -qE "$PATTERN"; then echo "SELFTEST FAIL: false positive on clean line: [$s]"; rc=2; fi
  done
  return $rc
}

if ! selftest; then
  echo "FAIL: no-hardcoded-strings guard self-test failed (regex needs fixing before use)."
  exit 2
fi

fail=0
while IFS= read -r -d '' f; do
  case "$f" in apps/*/lib/*.dart) ;; *) continue ;; esac
  [ "$f" = "$SELF" ] && continue
  lines="$(grep -nE "$PATTERN" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ',')"
  if [ -n "$lines" ]; then
    echo "BLOCK  hardcoded user-facing string in $f at line(s): ${lines%,} (RF-020: use AppLocalizations from packages/l10n)"
    fail=1
  fi
done < <(git ls-files --cached --others --exclude-standard -z -- 'apps/**/*.dart')

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "FAIL: hardcoded user-facing string(s) in scaffolded app shells. Render text"
  echo "      via AppLocalizations (packages/l10n), e.g. Text(l10n.posAppTitle) (RF-020)."
  exit 1
fi

echo "OK: no hardcoded user-facing strings in scaffolded app shells (self-test passed)."
exit 0
