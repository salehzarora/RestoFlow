#!/usr/bin/env bash
# ============================================================================
# RestoFlow — local secret-leak scan  (RF-013)
#
# Purpose: a fast, dependency-free guard that fails if a real secret could be
# committed. It scans files that COULD enter git (tracked + untracked, but NOT
# gitignored — `--exclude-standard`), so a properly ignored `.env.local` is
# never a finding, while an un-ignored secret IS.
#
# It checks three things:
#   0) Provider / vendor-PRIVATE PATHS (BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001).
#      A path inside one of the private families is refused by its path alone,
#      before any content is read - when it is tracked (force-added included)
#      or untracked and not ignored, and whatever the file is called (a
#      "*.example" name does not help). Such a path is then left out of checks
#      1) and 2).
#   1) Forbidden secret-bearing FILENAMES that are not gitignored
#      (.env, *.pem, *.key, *service_role*, signing_keys.json, ...).
#   2) Credential VALUE patterns inside file CONTENTS (JWTs, sb_secret_ keys,
#      AWS / Google keys, PEM private keys, Slack tokens).
#
# It NEVER prints a matched secret value — only "<file>:<line>" locations — and
# for a private path only the entry that matched, never the names below it.
# It is a PATTERN scanner: it knows the paths and value shapes listed in this
# file and nothing else. A clean run is not proof that no credential exists.
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

# ---- 0) provider / vendor-private paths ------------------------------------
# BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001. Private payment-provider material (raw
# provider e-mails and their attachments, credential packages, test-card data,
# private research) is kept OUTSIDE this repository. The matching .gitignore
# block keeps a stray copy from being staged by a plain `git add`; this check is
# the backstop for what an ignore rule cannot stop: a file that is already
# tracked, a `git add -f`, a name that Git matched with another case rule, or an
# ignore block that was edited away.
#
#   rule  kind  pattern (ASCII case ignored)            covers
#   P1    path  docs/dejavoo  docs/cardcom              the entry at that path, from the
#               docs/payplus                            repository root, and all below it
#   P2    path  docs/PAYMENTS_CARD_PRESENT_RESEARCH.md  the same, for that document
#   P3    name  vendor-private  provider-private        an entry with exactly that name,
#               zcredit-raw                             at any depth, and all below it
#
# An "entry" is whatever Git lists under that name: normally a folder with its
# files, but a file, a symbolic link or a nested repository of that name is
# refused as well.
#
# Every rule is a PATH/NAME rule: it looks at the path Git reports and never
# opens the file. There is NO provider CONTENT rule. The provider's secrets have
# no public, recognisable shape - the configuration schema in
# supabase/functions/pos-card-charge/lib/config.mjs accepts any run of 1 to 256
# printable ASCII characters without blanks - and no pattern may be learnt from
# the private material itself. Checks 1), 1b) and 2) keep their rules and
# patterns and are applied to the paths outside these families.
#
# P1 and P2 are where the material used to sit. Of P3, vendor-private and
# zcredit-raw are folder names of the private store; provider-private is the
# twin spelling, added so that either word is safe. Narrow on purpose: `vendor/`
# and `provider/` folders and zcredit-named source, tests and documents are NOT
# matched, nor is a longer or shorter name (`vendor-private-notes/`,
# `docs/dejavoo.md`). The limit of a path rule: private material saved under any
# other name or folder is not recognised.
#
# A refused path is reported by the entry that matched only. The names below it
# may themselves be private, and this output lands in CI logs.
PRIVATE_ROOT=""
# Returns 0 when path $1 is, or lies below, an entry of a private family, and
# then sets PRIVATE_ROOT to the path up to and including that entry, in the
# spelling Git reported, with a trailing "/" when the path goes on below it.
# Builtins only: it runs once for every listed path. The C locale makes "case
# ignored" mean the 26 ASCII letters on every machine, whatever language the
# shell is set to.
private_path() {
  local p="$1" rest seg acc rc=1
  local LC_ALL=C
  shopt -s nocasematch
  # A "/" added at the end (and, for P3, at the start) lets one pattern per name
  # match both the entry itself and everything below it, and nothing else.
  case "$p/" in
    docs/dejavoo/*|docs/cardcom/*|docs/payplus/*|docs/PAYMENTS_CARD_PRESENT_RESEARCH.md/*)   # P1, P2
      rest="${p#*/}"; seg="${rest%%/*}"
      if [ "$rest" = "$seg" ]; then PRIVATE_ROOT="$p"; else PRIVATE_ROOT="${p%%/*}/$seg/"; fi
      rc=0 ;;
  esac
  if [ "$rc" -ne 0 ]; then
    case "/$p/" in
      */vendor-private/*|*/provider-private/*|*/zcredit-raw/*)                               # P3
        acc=""; rest="$p"
        while :; do
          seg="${rest%%/*}"
          case "$seg" in
            vendor-private|provider-private|zcredit-raw)
              if [ "$rest" = "$seg" ]; then PRIVATE_ROOT="$acc$seg"; else PRIVATE_ROOT="$acc$seg/"; fi
              rc=0; break ;;
          esac
          [ "$rest" != "$seg" ] || break
          acc="$acc$seg/"; rest="${rest#*/}"
        done ;;
    esac
  fi
  shopt -u nocasematch
  return "$rc"
}
# NUL-separated paths in; the paths OUTSIDE the private families out.
drop_private() {
  local f
  while IFS= read -r -d '' f; do
    private_path "$f" || printf '%s\0' "$f"
  done
}
# NUL-separated paths in; one "<state><TAB><matched entry>" line out for every
# path inside a family. Control characters in the entry are shown as "?".
list_private() {
  local f
  while IFS= read -r -d '' f; do
    private_path "$f" && printf '%s\t%s\n' "$1" "${PRIVATE_ROOT//[[:cntrl:]]/?}"
  done
  return 0
}

# The verdict is taken from the raw list, before anything is sorted or counted,
# and a listing that fails is itself a finding. This check must not pass because
# a command broke: the paths it would have reported are left out of the later
# checks, so nothing else would report them.
private_hits="$(
  { git ls-files --cached -z | list_private tracked; } &&
  { git ls-files --others --exclude-standard -z | list_private untracked; }
)" || { echo "BLOCK  provider/vendor-private path check: Git could not list the files"; fail=1; }
if [ -n "$private_hits" ]; then
  fail=1
  printf '%s\n' "$private_hits" | LC_ALL=C sort | LC_ALL=C uniq -c | while read -r count state root; do
    case "$root" in
      */) root="${root}<redacted>" ;;
    esac
    echo "BLOCK  provider/vendor-private path ($state, $count path(s)): $root"
  done
  echo "       Private provider/vendor material is kept outside the repository. A \"*.example\""
  echo "       name or \`git add -f\` does not make such a path acceptable (docs/DEPLOYMENT.md, section 7)."
fi

# Checks 1), 1b) and 2) read this list: the candidate files WITHOUT the private
# paths. Those are refused above; neither their names nor their contents may
# reach a later check or its output.
scan_list() { git ls-files --cached --others --exclude-standard -z | drop_private; }

# ---- 1) forbidden filenames that are NOT gitignored ------------------------
while IFS= read -r -d '' f; do
  case "$f" in
    *.example) continue ;;   # placeholder templates are allowed
  esac
  base="$(basename -- "$f")"
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
  | xargs -0 grep -IHnEi -- "${SIGNING_KEYS}[[:space:]]*=" 2>/dev/null \
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
  | xargs -0 grep -IHnE -- "$VALUE_PATTERNS" 2>/dev/null \
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
