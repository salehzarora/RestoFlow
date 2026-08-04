#!/usr/bin/env bash
# ============================================================================
# RELEASE-KEY-AND-PIPELINE-001 — focused test for the signing-secret guard.
#
# A guard nobody has watched FAIL is not a guard. This proves, in both
# directions, that tools/check_secrets.sh:
#   1. passes on the real repository,
#   2. allows the placeholder *.example template and documented placeholders,
#   3. allows Gradle CODE that merely READS storePassword/keyPassword,
#   4. BLOCKS a realistic signing-properties file (by name),
#   5. BLOCKS a literal storePassword/keyPassword value,
#   6. BLOCKS a tracked binary keystore (by extension).
#
# Fixtures live in a THROWAWAY git repo under the system temp dir, never in the
# real tree — check_secrets.sh resolves its root from the current directory, so
# running it there scans only the fixtures. (An earlier version used
# `git worktree add` on this repository; that copies the whole tree and holds
# the index lock, which is far too slow for a focused test.)
#
# Run:  bash tools/test_check_secrets_signing.sh
# ============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
GUARD="$ROOT/tools/check_secrets.sh"
pass=0
fail=0

ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init --quiet
git -C "$TMP" config user.email t@t; git -C "$TMP" config user.name t

# Exit code of the guard when run against the fixture repo.
guard() { ( cd "$TMP" && bash "$GUARD" >/dev/null 2>&1; echo $?; ); }

echo "signing-secret guard test"

# 1. the REAL repository still passes
[ "$(cd "$ROOT" && bash "$GUARD" >/dev/null 2>&1; echo $?)" = "0" ] \
  && ok "real repository passes" || bad "real repository must pass"

# 2. an empty fixture repo passes (baseline)
[ "$(guard)" = "0" ] && ok "clean fixture repo passes" || bad "clean fixture repo must pass"

# 3. the placeholder template is allowed
cp "$ROOT/tools/android_release/signing.properties.example" "$TMP/signing.properties.example"
[ "$(guard)" = "0" ] \
  && ok "placeholder .example template is allowed" || bad ".example template must be allowed"

# 4. Gradle code that READS the properties is allowed (not a literal secret)
cat > "$TMP/build.gradle.kts" <<'EOF'
storePassword = props.getProperty("storePassword")
keyPassword = props.getProperty("keyPassword")
EOF
[ "$(guard)" = "0" ] \
  && ok "Gradle code reading the properties is allowed" || bad "property-reading code must not be flagged"

# 5. documented placeholders are allowed
cat > "$TMP/notes.md" <<'EOF'
storePassword=<CHANGE_ME>
keyPassword=YOUR_KEY_PASSWORD
EOF
[ "$(guard)" = "0" ] \
  && ok "documented placeholders are allowed" || bad "placeholders must not be flagged"
rm -f "$TMP/notes.md"

# 6. a LITERAL password IS blocked
cat > "$TMP/notes.md" <<'EOF'
storePassword=Tr0ub4dor-and-3-horses
EOF
[ "$(guard)" = "1" ] \
  && ok "literal storePassword value is blocked" || bad "literal password must be blocked"
rm -f "$TMP/notes.md"

# 7. a realistic signing-properties file is blocked by NAME
cat > "$TMP/signing.properties" <<'EOF'
storeFile=C:/keys/restoflow-production.jks
keyAlias=restoflow-production
EOF
[ "$(guard)" = "1" ] \
  && ok "signing.properties is blocked by name" || bad "signing.properties must be blocked"
rm -f "$TMP/signing.properties"

# 8. a binary keystore is blocked by extension
printf '\x30\x82\x04\x00binary-keystore-bytes' > "$TMP/restoflow-production.jks"
[ "$(guard)" = "1" ] \
  && ok "tracked .jks keystore is blocked" || bad ".jks keystore must be blocked"
rm -f "$TMP/restoflow-production.jks"

echo ""
echo "signing-secret guard test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
