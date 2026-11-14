#!/usr/bin/env bash
# ============================================================================
# BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001 — focused test for the provider /
# vendor-private path rules of tools/check_secrets.sh and for the matching
# block in .gitignore.
#
# A guard nobody has watched FAIL is not a guard. This proves, in both
# directions, that
#   1. legitimate provider source, documents, vendored libraries and ordinary
#      placeholder templates stay visible to Git and pass the guard, and that a
#      different name or place stays outside the rules (exact boundaries),
#   2. Git ignores every private path form (plain, nested, with spaces, and a
#      file that is itself named like a private folder), by a rule of the new
#      block,
#   3. a private path is refused when it is force-added, when it was tracked
#      before the ignore rule existed, and when it is untracked while Git does
#      not ignore it - a binary file and a "*.example" name included,
#   4. the guard ignores ASCII case, and only ASCII case, and refuses index
#      entries that a file system may not hold: a line break in a folder name,
#      a symbolic link and a nested repository named like a private folder,
#   5. a refused path is neither named nor read: no file name below the matched
#      entry and no value from inside it reaches the guard's output,
#   6. the established env / key / signing / credential-value checks still
#      block, still redact, and still allow a placeholder template,
#   7. the check does not pass because a command broke: with a failing `sort`
#      and with an unreadable index the run still ends in exit 1,
#   8. a root file named like an option (an empty `-q`) does not switch off
#      the content checks: a literal signing value and a credential-shaped
#      value are still reported, with the files tracked and untracked, and a
#      clean repository holding `-q` passes without a basename error.
#
# What a run does not prove: it shows the behaviour on the machine and shell it
# is started on, nothing about another one. The "only ASCII case" assertion of
# item 4 is meaningful only where the C.UTF-8 locale exists; elsewhere it
# passes without proving anything.
#
# Every fixture is SYNTHETIC and is generated here, inside throwaway Git
# repositories under the system temp directory. Nothing is copied from real
# provider material and nothing is added to the real repository. Values that
# look like credentials are put together from harmless parts at run time, so
# this file holds none.
#
# Run:  bash tools/test_check_secrets_provider.sh
# ============================================================================
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
GUARD="$ROOT/tools/check_secrets.sh"
IGNORE="$ROOT/.gitignore"
# From here on every Git command names a throwaway repository by path. Drop the
# repository-pointing variables (a Git hook exports them) so that none of them
# can turn a fixture command towards the real repository.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
pass=0
fail=0

ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "${TMP:?}"' EXIT
if git -C "$TMP" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "refusing to run: the temporary directory lies inside a Git work tree"; exit 2
fi
real_index() { git -C "$ROOT" --no-optional-locks ls-files --stage | cksum; }
INDEX_BEFORE="$(real_index)"

REPO=""
repos=0
new_repo() {            # new_repo [with-ignore]: a fresh throwaway repository in $REPO
  repos=$((repos + 1)); REPO="$TMP/repo$repos"
  mkdir -p "$REPO"
  git -C "$REPO" init --quiet || { echo "git init failed"; exit 2; }
  git -C "$REPO" config user.email t@t
  git -C "$REPO" config user.name t
  git -C "$REPO" config core.autocrlf false
  git -C "$REPO" config commit.gpgsign false
  # Nothing of the developer's own Git setup may decide a result: no hooks, and
  # no personal ignore file (it could hide a fixture from the guard).
  git -C "$REPO" config core.hooksPath "$TMP/no-hooks"
  git -C "$REPO" config core.excludesFile "$TMP/no-excludes"
  if [ "$(git -C "$REPO" rev-parse --show-toplevel)" = "$ROOT" ]; then
    echo "refusing to run: a fixture repository resolved to the real repository"; exit 2
  fi
  if [ "${1:-}" = "with-ignore" ]; then cp "$IGNORE" "$REPO/.gitignore"; fi
}
put() {                 # put <path> [line...]: a synthetic text file inside $REPO
  local path="$REPO/$1"; shift
  mkdir -p "${path%/*}"
  printf '%s\n' "$@" > "$path"
}
OUT=""
RC=0
run_guard() { OUT="$(cd "$REPO" && bash "$GUARD" 2>&1)"; RC=$?; }
show()   { printf '%s\n' "$OUT" | sed 's/^/        | /'; }
rc_is()  { if [ "$RC" = "$1" ]; then ok "$2"; else bad "$2 (exit $RC, expected $1)"; show; fi; }
line()   { if printf '%s\n' "$OUT" | grep -qxF -- "$1"; then ok "$2"; else bad "$2"; show; fi; }
silent() { if printf '%s\n' "$OUT" | grep -qF -- "$1"; then bad "$2"; show; else ok "$2"; fi; }
blocks() { printf '%s\n' "$OUT" | grep -c '^BLOCK  ' || true; }
count_is() { if [ "$(blocks)" = "$1" ]; then ok "$2"; else bad "$2 (expected $1 BLOCK lines, found $(blocks))"; show; fi; }
# The .gitignore pattern that makes Git ignore the path (empty: not ignored;
# "error": Git failed). A last match on a "!" pattern means NOT ignored.
ignored_by() {
  local out rc pattern
  out="$(git -C "$REPO" check-ignore -v "$@" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) pattern="$(printf '%s\n' "$out" | tr -d '\r' | cut -f1 | cut -d: -f3-)"
       case "$pattern" in
         '!'*) echo "" ;;
         *) printf '%s\n' "$pattern" ;;
       esac ;;
    1) echo "" ;;
    *) echo "error" ;;
  esac
}

# Synthetic values, put together from harmless parts.
part="SYNTHETICSYNTHETIC"
FAKE_JWT="ey""J${part}.ey""J${part}.${part}"
FAKE_PEM="-----BEGIN PRIV""ATE KEY-----"
FAKE_PW="Synthetic-Passphrase-0001"
SP="store"; SP="${SP}Password"
NAME_MARK="NAMEMARK7Q2"
BODY_MARK="BODYMARK9Z4"
P="BLOCK  provider/vendor-private path"

echo "provider / vendor-private path guard test"

# ---- 1. legitimate material and exact boundaries ---------------------------
ALLOWED=(
  "README.md"
  ".env.example"
  "config/service.env.example"
  "supabase/functions/pos-card-charge/lib/provider/zcredit_profile.mjs"
  "supabase/functions/pos-card-charge/test/zcredit_profile.test.mjs"
  "supabase/functions/storefront-media-publish/vendor/README.md"
  "tools/storefront_content_unicode/vendor/LICENSE.txt"
  "apps/pos/lib/src/state/card_provider.dart"
  "docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md"
  "docs/Card terminal notes.md"
)
BOUNDARY=(              # another name or another place: outside the rules by design
  "docs/dejavoo.md"
  "docs/dejavoo-terminal-notes.md"
  "docs/dejavoo2/readme.md"
  "docs/payments/dejavoo/overview.md"
  "docs/PAYMENTS_CARD_PRESENT.md"
  "docs/archive/PAYMENTS_CARD_PRESENT_RESEARCH.md"
  "vendor/private/notes.txt"
  "vendor-private.md"
  "vendor-private-notes/readme.md"
  "my-vendor-private/readme.md"
  "provider-privates/readme.md"
  "zcredit-raw.txt"
  "zcredit-rawdata/readme.md"
)
new_repo with-ignore
for f in "${ALLOWED[@]}" "${BOUNDARY[@]}"; do put "$f" "API_KEY=<CHANGE_ME>" "synthetic fixture"; done
wrong=""
for f in "${ALLOWED[@]}" "${BOUNDARY[@]}"; do
  [ -z "$(ignored_by -- "$f")" ] || wrong="$wrong [$f]"
done
[ -z "$wrong" ] && ok "Git keeps all ${#ALLOWED[@]} legitimate and ${#BOUNDARY[@]} boundary paths visible" \
  || bad "Git must not ignore:$wrong"
run_guard
rc_is 0 "the guard passes legitimate provider source, documents, vendored libraries and placeholder templates"
count_is 0 "no path outside the rules is reported"

# ---- 2. Git ignores the private path forms ---------------------------------
PRIVATE=(
  "docs/dejavoo/readme.txt"
  "docs/dejavoo/Terminal setup guide.txt"
  "docs/dejavoo/terminal-settings.json.example"
  "docs/cardcom/deep/er/offer.txt"
  "docs/payplus/Quote for client.txt"
  "docs/PAYMENTS_CARD_PRESENT_RESEARCH.md"
  "vendor-private/manifest.txt"
  "vendor-private/.env.example"
  "tools/scratch/vendor-private/zcredit-raw/dejavoo/mail 01.eml"
  "apps/pos/zcredit-raw/export.json"
  "libs/provider-private"
)
BINARY="provider-private/keys/terminal.bin"
new_repo with-ignore
for f in "${PRIVATE[@]}"; do put "$f" "synthetic fixture" "$BODY_MARK"; done
mkdir -p "$REPO/provider-private/keys"
printf 'PK\003\004\000\001synthetic\000bytes\377\376' > "$REPO/$BINARY"
wrong=""
for f in "${PRIVATE[@]}" "$BINARY"; do
  case "$(ignored_by -- "$f")" in
    /docs/dejavoo|/docs/cardcom|/docs/payplus|/docs/PAYMENTS_CARD_PRESENT_RESEARCH.md) ;;
    vendor-private|provider-private|zcredit-raw) ;;
    *) wrong="$wrong [$f]" ;;
  esac
done
[ -z "$wrong" ] && ok "Git ignores all $(( ${#PRIVATE[@]} + 1 )) private path forms, each by a rule of the new block" \
  || bad "not ignored by a rule of the new block:$wrong"
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=all | grep -v -x -F '?? .gitignore')" ] \
  && ok "git status shows none of them as untracked" || bad "git status must not list an ignored private path"
run_guard
rc_is 0 "ignored and untracked private files are not a finding (a plain git add cannot stage them)"

# ---- 3a. force-added ---------------------------------------------------------
git -C "$REPO" add -f -- "${PRIVATE[@]}" "$BINARY"
run_guard
rc_is 1 "force-added private paths are refused"
line "$P (tracked, 3 path(s)): docs/dejavoo/<redacted>" "docs/dejavoo: plain name, a name with spaces and a *.example name"
line "$P (tracked, 1 path(s)): docs/cardcom/<redacted>" "docs/cardcom: a nested path"
line "$P (tracked, 1 path(s)): docs/payplus/<redacted>" "docs/payplus: a name with spaces"
line "$P (tracked, 1 path(s)): docs/PAYMENTS_CARD_PRESENT_RESEARCH.md" "the research document at the repository root"
line "$P (tracked, 2 path(s)): vendor-private/<redacted>" "vendor-private at the root, .env.example included"
line "$P (tracked, 1 path(s)): tools/scratch/vendor-private/<redacted>" "vendor-private nested, reported once by its outermost private entry"
line "$P (tracked, 1 path(s)): apps/pos/zcredit-raw/<redacted>" "zcredit-raw nested"
line "$P (tracked, 1 path(s)): provider-private/<redacted>" "provider-private: a binary file is refused by its path"
line "$P (tracked, 1 path(s)): libs/provider-private" "a file that is itself named like a private folder"
count_is 9 "exactly the nine private entries are reported, nothing twice"
silent "$BODY_MARK" "no content of a refused file is printed"
silent "terminal-settings" "no file name below a private entry is printed"

# ---- 3b. tracked before the ignore rule existed ----------------------------
new_repo
put "docs/dejavoo/old-copy.txt" "synthetic fixture"
git -C "$REPO" add -- docs/dejavoo/old-copy.txt
git -C "$REPO" commit --quiet -m "fixture"
cp "$IGNORE" "$REPO/.gitignore"
[ -n "$(git -C "$REPO" ls-files -- docs/dejavoo/old-copy.txt)" ] \
  && [ "$(ignored_by --no-index -- docs/dejavoo/old-copy.txt)" = "/docs/dejavoo" ] \
  && ok "an ignore rule does not untrack: the file stays tracked although the rule matches it" \
  || bad "the committed file must stay tracked while the rule matches it"
run_guard
rc_is 1 "a private path that was tracked before the rule is refused"
line "$P (tracked, 1 path(s)): docs/dejavoo/<redacted>" "it is reported as tracked"

# ---- 3c. untracked while Git does not ignore it ----------------------------
new_repo
put "vendor-private/notes.txt" "synthetic fixture"
put "docs/payplus/offer.txt" "synthetic fixture"
run_guard
rc_is 1 "without the ignore block an untracked private path is still refused"
line "$P (untracked, 1 path(s)): vendor-private/<redacted>" "vendor-private is reported as untracked"
line "$P (untracked, 1 path(s)): docs/payplus/<redacted>" "docs/payplus is reported as untracked"

# ---- 4a. ASCII case ----------------------------------------------------------
MIXED=(
  "docs/CardCom/Offer.TXT"
  "docs/payments_card_present_research.MD"
  "Vendor-Private/a.txt"
  "x/ZCREDIT-RAW/b.txt"
  "PROVIDER-PRIVATE/c.txt"
)
new_repo with-ignore
for f in "${MIXED[@]}"; do put "$f" "synthetic fixture"; done
git -C "$REPO" add -f -- "${MIXED[@]}"
run_guard
rc_is 1 "private paths in another letter case are refused"
line "$P (tracked, 1 path(s)): docs/CardCom/<redacted>" "docs/CardCom"
line "$P (tracked, 1 path(s)): docs/payments_card_present_research.MD" "the research document in lower case"
line "$P (tracked, 1 path(s)): Vendor-Private/<redacted>" "Vendor-Private"
line "$P (tracked, 1 path(s)): x/ZCREDIT-RAW/<redacted>" "x/ZCREDIT-RAW"
line "$P (tracked, 1 path(s)): PROVIDER-PRIVATE/<redacted>" "PROVIDER-PRIVATE"

# ---- 4b. index entries a file system may not hold (no working file is made) --
# A line break in a folder name, the research document's name as a folder, a
# symbolic link and a nested repository named like a private folder, a symbolic
# link at the path of a P1 folder, and a look-alike name whose capital I carries
# a dot (two bytes, not ASCII). The guard runs under a UTF-8 locale here: only
# there could the look-alike match.
new_repo
git -C "$REPO" config core.protectNTFS false
blob="$(printf 'synthetic fixture\n' | git -C "$REPO" hash-object -w --stdin)"
{ printf '100644 %s\tline\nbreak/vendor-private/a.txt\0' "$blob"
  printf '100644 %s\tdocs/PAYMENTS_CARD_PRESENT_RESEARCH.md/part.txt\0' "$blob"
  printf '120000 %s\tlinks/vendor-private\0' "$blob"
  printf '160000 %s\tmodules/zcredit-raw\0' "$blob"
  printf '120000 %s\tdocs/cardcom\0' "$blob"
  printf '100644 %s\tVENDOR-PR\304\260VATE/b.txt\0' "$blob"
} | git -C "$REPO" update-index -z --add --index-info
[ "$(git -C "$REPO" ls-files --cached -z | tr -cd '\0' | wc -c | tr -d ' ')" = "6" ] \
  && ok "the six index entries exist" || bad "the six index entries could not be made"
OUT="$(cd "$REPO" && LC_ALL=C.UTF-8 bash "$GUARD" 2>&1)"; RC=$?
rc_is 1 "index entries with unusual names and types are refused"
line "$P (tracked, 1 path(s)): line?break/vendor-private/<redacted>" "a line break in the reported entry is shown as ?"
line "$P (tracked, 1 path(s)): docs/PAYMENTS_CARD_PRESENT_RESEARCH.md/<redacted>" "the research document's name as a folder"
line "$P (tracked, 1 path(s)): links/vendor-private" "a symbolic link named like a private folder"
line "$P (tracked, 1 path(s)): modules/zcredit-raw" "a nested repository named like a private folder"
line "$P (tracked, 1 path(s)): docs/cardcom" "a symbolic link at the path of a P1 folder"
count_is 5 "five entries, one line each: the line break did not split a line, the look-alike is not matched"
silent "VENDOR-PR" "the look-alike name is not reported (only ASCII case is ignored)"

# ---- 5. a refused path is neither named nor read ---------------------------
new_repo
put "docs/dejavoo/$NAME_MARK-terminal.txt" "token: $FAKE_JWT" "$BODY_MARK"
put "vendor-private/keys/$NAME_MARK.key" "$FAKE_PEM" "$BODY_MARK"
put "docs/payplus/$NAME_MARK.env" "TOKEN=$BODY_MARK"
put "docs/cardcom/signing.properties" "$SP=$FAKE_PW"
put "provider-private/$NAME_MARK.example" "token: $FAKE_JWT"
put "app/settings.txt" "synthetic fixture" "token: $FAKE_JWT"
run_guard
rc_is 1 "private files holding credential-shaped values are refused"
line "BLOCK  possible credential value in app/settings.txt at line(s): 2 (value redacted)" \
  "control: the same value in an ordinary file is found by the content check"
count_is 6 "five private entries and the one control finding, nothing else"
silent "$NAME_MARK" "no private file name is printed"
silent "signing.properties" "a private file is not reported again by a file-name check"
silent "$BODY_MARK" "no private content is printed"
silent "$FAKE_JWT" "no credential-shaped value is printed"
silent "$FAKE_PW" "no signing value is printed"
silent "possible credential value in docs/" "the content check did not read docs/dejavoo"
silent "possible credential value in vendor-private" "the content check did not read vendor-private"
silent "possible credential value in provider-private" "the content check did not read provider-private"
silent "Android signing password in" "the signing check did not read docs/cardcom"

# ---- 6. the established checks still block and still redact ----------------
new_repo
put "prod.env" "X=1"
put "server.key" "synthetic fixture"
put "signing.properties" "keyAlias=synthetic"
put "notes.md" "$SP=$FAKE_PW"
put "app/config.txt" "one" "two" "token: $FAKE_JWT"
put "template.env.example" "API_KEY=<CHANGE_ME>"
run_guard
rc_is 1 "the established checks still fail the run"
line "BLOCK  un-ignored env file (may hold secrets): prod.env" "env file by name"
line "BLOCK  un-ignored secret-bearing file: server.key" "key file by extension"
line "BLOCK  un-ignored Android signing-properties file: signing.properties" "signing-properties file by name"
line "BLOCK  Android signing password in notes.md at line 1 (value redacted)" "literal signing value, redacted"
line "BLOCK  possible credential value in app/config.txt at line(s): 3 (value redacted)" "credential-shaped value, redacted"
line "FAIL: potential secret(s) detected. Remove/ignore them before committing." "the closing FAIL line is unchanged"
count_is 5 "the placeholder template is not reported"
silent "$FAKE_JWT" "the credential-shaped value is not printed"
silent "$FAKE_PW" "the signing value is not printed"
rm -f "$REPO/prod.env" "$REPO/server.key" "$REPO/signing.properties" "$REPO/notes.md" "$REPO/app/config.txt"
run_guard
rc_is 0 "with the findings removed the run is clean again"
line "OK: no committable secrets detected (scanned tracked + non-ignored files)." "the closing OK line is unchanged"

# ---- 7. a broken command must not turn the check into a pass ----------------
# The private file below is left out of the later checks, so only the path
# check can report it: it has to do so even when `sort` fails, and it has to
# say so when Git cannot list the files at all.
new_repo
put "vendor-private/notes.txt" "token: $FAKE_JWT"
mkdir -p "$TMP/broken-bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP/broken-bin/sort"
chmod +x "$TMP/broken-bin/sort"
OUT="$(cd "$REPO" && PATH="$TMP/broken-bin:$PATH" bash "$GUARD" 2>&1)"; RC=$?
rc_is 1 "with a failing sort a private path still fails the run"
silent "$FAKE_JWT" "and its content is still not printed"
printf 'not an index\n' > "$REPO/.git/index"
run_guard
rc_is 1 "an unreadable index is a finding, not a clean run"
line "BLOCK  provider/vendor-private path check: Git could not list the files" "the failed listing is reported"

# ---- 8. a root file named like an option must not switch the content checks off
# Git lists an empty root file named -q first. While the file names reached grep
# as arguments without a "--" in front of them, grep took it as its option -q
# (quiet) and printed nothing, so both content checks passed. Each case holds
# only what it tests - no forbidden file name and no private path - so nothing
# but the content check can fail the run. Every case runs twice: with the files
# untracked (and not ignored), and with them tracked.
in_state() {            # in_state <tracked|untracked> <path>...: Git lists these paths in that state
  local state="$1" listed
  shift
  if [ "$state" = "tracked" ]; then
    listed="$(git -C "$REPO" ls-files --cached -z -- "$@" | tr -cd '\0' | wc -c | tr -d ' ')"
  else
    listed="$(git -C "$REPO" ls-files --others --exclude-standard -z -- "$@" | tr -cd '\0' | wc -c | tr -d ' ')"
  fi
  if [ "$listed" = "$#" ]; then ok "$state: Git lists $* as $state"; else bad "$state: Git lists $listed of the $# paths $* as $state"; fi
}
track() {               # track <tracked|untracked> <path>...: commit the paths when the case is the tracked one
  local state="$1"
  shift
  if [ "$state" = "tracked" ]; then
    git -C "$REPO" add -- "$@" && git -C "$REPO" commit --quiet -m "fixture"
  fi
}
for state in untracked tracked; do
  new_repo
  : > "$REPO/-q"
  put "app/notes.md" "$SP=$FAKE_PW"
  track "$state" -q app/notes.md
  in_state "$state" -q app/notes.md
  run_guard
  rc_is 1 "$state, -q present: a literal signing value still fails the run"
  line "BLOCK  Android signing password in app/notes.md at line 1 (value redacted)" \
    "$state, -q present: the signing finding is reported"
  count_is 1 "$state, -q present: the signing finding is the only finding"
  silent "$FAKE_PW" "$state, -q present: the signing value is not printed"

  new_repo
  : > "$REPO/-q"
  put "app/config.txt" "synthetic fixture" "token: $FAKE_JWT"
  track "$state" -q app/config.txt
  in_state "$state" -q app/config.txt
  run_guard
  rc_is 1 "$state, -q present: a credential-shaped value still fails the run"
  line "BLOCK  possible credential value in app/config.txt at line(s): 2 (value redacted)" \
    "$state, -q present: the credential-value finding is reported"
  count_is 1 "$state, -q present: the credential-value finding is the only finding"
  silent "$FAKE_JWT" "$state, -q present: the credential-shaped value is not printed"

  new_repo
  : > "$REPO/-q"
  put "app/readme.md" "synthetic fixture"
  track "$state" -q app/readme.md
  in_state "$state" -q app/readme.md
  run_guard
  rc_is 0 "$state, -q present: a clean repository passes"
  line "OK: no committable secrets detected (scanned tracked + non-ignored files)." \
    "$state, -q present: the closing OK line is printed"
  silent "basename" "$state, -q present: no basename option error"
done

# ---- the real repository was not touched -----------------------------------
[ "$(real_index)" = "$INDEX_BEFORE" ] && ok "the real repository's index is the same before and after" \
  || bad "the real repository's index changed during the test"

echo ""
echo "provider / vendor-private path guard test: $pass passed, $fail failed ($repos throwaway repositories)"
[ "$fail" -eq 0 ] || exit 1
exit 0
