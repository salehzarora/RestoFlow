#!/usr/bin/env bash
# ============================================================================
# RestoFlow - no-floating-point-money guard  (RF-011, DECISION D-007)
#
# Money is ALWAYS integer minor units (DECISION D-007). The money TYPE lives in
# packages/money (ticket RF-036); no package may model money with double/num/
# float. This guard fails if a float type (double/num/float) types a
# money-named identifier, e.g.:
#       double totalMinor;     final double priceMinor = 0;
#       double cashTendered;   amountMinor: double
# Money terms are matched as SUBSTRINGS (no word boundaries) so camelCase and
# snake_case identifiers (totalMinor, price_minor, cashTendered) are covered;
# the float TYPE tokens keep word boundaries so "enum"/"number" never match.
#
# Scans tracked + non-ignored *.dart files under apps/ and packages/.
# Location-only output; never prints code. Exit codes:
#   0 = clean   1 = violation found   2 = the guard's own self-test failed
# Run:  bash tools/check_no_float_money.sh   (Windows: Git Bash)
# ============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 2
SELF="tools/check_no_float_money.sh"

# Money terms matched as substrings. Curated to strongly imply money while
# minimising false positives from unrelated identifiers.
MONEY='price|amount|subtotal|total|money|minor|cost|balance|tendered|discount|payment|cash|gross|refund|currency'

# Branch A: float type then a money-named identifier  ->  double totalMinor
# Branch B: a money-named identifier then ": floatType" ->  totalMinor: double
PATTERN="\b(double|num|float)\b[[:space:]]+[A-Za-z0-9_]*(${MONEY})|[A-Za-z0-9_]*(${MONEY})[A-Za-z0-9_]*[[:space:]]*:[[:space:]]*\b(double|num|float)\b"

# ---- self-test: guard MUST catch real violations and MUST NOT flag clean ----
selftest() {
  local rc=0 s
  local must_match=(
    'double totalMinor;'
    'final double priceMinor = 0.0;'
    'double cashTendered;'
    'double total_minor = 0;'
    'amountMinor: double'
    'num grandTotalAmount = 0;'
  )
  local must_not=(
    'int totalMinor;'
    'final int priceMinor = 0;'
    'enum AppEnvironment { dev, staging, prod }'
    'double zoomScale = 1.0;'
    '// running total of the price shown to the cashier'
  )
  for s in "${must_match[@]}"; do
    printf '%s\n' "$s" | grep -qEi "$PATTERN" || { echo "SELFTEST FAIL: missed real violation: [$s]"; rc=2; }
  done
  for s in "${must_not[@]}"; do
    if printf '%s\n' "$s" | grep -qEi "$PATTERN"; then echo "SELFTEST FAIL: false positive on clean line: [$s]"; rc=2; fi
  done
  return $rc
}

if ! selftest; then
  echo "FAIL: no-float-money guard self-test failed (regex needs fixing before use)."
  exit 2
fi

fail=0
while IFS= read -r -d '' f; do
  case "$f" in *.dart) ;; *) continue ;; esac
  [ "$f" = "$SELF" ] && continue
  lines="$(grep -nEi "$PATTERN" "$f" 2>/dev/null | cut -d: -f1 | tr '\n' ',')"
  if [ -n "$lines" ]; then
    echo "BLOCK  possible floating-point money in $f at line(s): ${lines%,} (DECISION D-007: integer minor units only)"
    fail=1
  fi
done < <(git ls-files --cached --others --exclude-standard -z -- 'apps/**/*.dart' 'packages/**/*.dart')

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "FAIL: floating-point money modeling detected. Money is integer minor units"
  echo "      (DECISION D-007); the money type lives in packages/money (RF-036)."
  exit 1
fi

echo "OK: no floating-point money modeling found under apps/ and packages/ (self-test passed)."
exit 0
