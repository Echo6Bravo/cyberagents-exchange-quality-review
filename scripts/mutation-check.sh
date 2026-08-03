#!/usr/bin/env bash
# mutation-check.sh -- prove a regression test is a REAL guard, not a tautology.
#
# A test that passes both WITH and WITHOUT the code it supposedly guards asserts nothing
# (e.g. it checks a string that also appears in static output). This script mechanizes the
# "revert the fix and confirm the test flips to FAIL" proof that quality-review dimension 11
# calls for: it runs your test command clean (must pass), applies a mutation to the target
# file, re-runs the test (must now FAIL), then ALWAYS restores the file.
#
# Usage:
#   mutation-check.sh --test "<cmd>" --file <path> --old "<str>" --new "<str>"
#   mutation-check.sh --test "<cmd>" --file <path> --delete-match "<substr>"
#   mutation-check.sh --test "<cmd>" --file <path> --delete-line <N>
#
#   --test         command that runs the test(s); its EXIT CODE is the signal (0=pass).
#   --file         source file to mutate (the code under guard).
#   --old/--new    replace the FIRST literal occurrence of <old> with <new>.
#   --delete-match delete every line containing <substr> (literal).
#   --delete-line  delete line number <N>.
#
# Exit codes:
#   0  the test is a REAL guard (passed clean, failed under mutation).
#   1  the test is NOT a guard (passed clean AND still passed under mutation) -- the finding.
#   2  usage / setup error, or the mutation did not change the file, or clean run didn't pass.
#
# Portable: bash 3.2+, POSIX tools (grep, sed via a temp copy, awk). No GNU-only flags.
set -u

PROG=$(basename "$0")
die() { printf '%s: ERROR: %s\n' "$PROG" "$1" >&2; usage >&2; exit 2; }
usage() {
  cat <<EOF
usage: $PROG --test "<cmd>" --file <path> ( --old "<s>" --new "<s>" | --delete-match "<s>" | --delete-line <N> )
EOF
}

TEST_CMD=""; FILE=""; OLD=""; NEW=""; NEW_SET=0; DELMATCH=""; DELLINE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --test) TEST_CMD="${2-}"; shift 2 ;;
    --file) FILE="${2-}"; shift 2 ;;
    --old) OLD="${2-}"; shift 2 ;;
    --new) NEW="${2-}"; NEW_SET=1; shift 2 ;;
    --delete-match) DELMATCH="${2-}"; shift 2 ;;
    --delete-line) DELLINE="${2-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$TEST_CMD" ] || die "missing --test"
[ -n "$FILE" ] || die "missing --file"
[ -f "$FILE" ] || die "file not found: $FILE"

# exactly one mutation mode
modes=0
[ -n "$OLD" ] && modes=$((modes+1))
[ -n "$DELMATCH" ] && modes=$((modes+1))
[ -n "$DELLINE" ] && modes=$((modes+1))
[ "$modes" -eq 1 ] || die "specify exactly one mutation: --old/--new, --delete-match, or --delete-line"
if [ -n "$OLD" ] && [ "$NEW_SET" -ne 1 ]; then die "--old requires --new"; fi
if [ -n "$DELLINE" ]; then
  case "$DELLINE" in (*[!0-9]*|"") die "--delete-line needs a positive integer" ;; esac
fi

# back up the target and guarantee restore on ANY exit (success, failure, interrupt).
BACKUP=$(mktemp "${TMPDIR:-/tmp}/mutchk.XXXXXX") || die "cannot create temp file"
cp "$FILE" "$BACKUP" || die "cannot back up $FILE"
restore() { cp "$BACKUP" "$FILE"; rm -f "$BACKUP"; }
trap 'restore' EXIT
trap 'restore; exit 2' INT TERM

run_test() { ( eval "$TEST_CMD" ) >/dev/null 2>&1; }

# 1) baseline: the test must PASS on the unmutated code, or we can't assess it.
if ! run_test; then
  printf '%s: the test command did NOT pass on the unmutated code -- cannot assess guard strength.\n' "$PROG" >&2
  printf '   Fix the suite so it is green first, then re-run.\n' >&2
  exit 2
fi

# 2) apply the mutation to a fresh copy, then move it into place.
TMP=$(mktemp "${TMPDIR:-/tmp}/mutchk.XXXXXX") || die "cannot create temp file"
if [ -n "$OLD" ]; then
  # literal first-occurrence replacement, done in awk (no regex/delimiter pitfalls).
  OLD="$OLD" NEW="$NEW" awk '
    BEGIN{ o=ENVIRON["OLD"]; n=ENVIRON["NEW"]; done=0 }
    { if(!done){ i=index($0,o); if(i>0){ $0=substr($0,1,i-1) n substr($0,i+length(o)); done=1 } } print }
    END{ if(!done) exit 3 }
  ' "$FILE" > "$TMP"
  st=$?
  if [ "$st" -eq 3 ]; then rm -f "$TMP"; die "--old string not found in $FILE (nothing mutated)"; fi
elif [ -n "$DELMATCH" ]; then
  DELMATCH="$DELMATCH" awk '{ if(index($0,ENVIRON["DELMATCH"])>0){next} print }' "$FILE" > "$TMP"
else
  DELLINE="$DELLINE" awk 'NR!=ENVIRON["DELLINE"]{print}' "$FILE" > "$TMP"
fi

# the mutation must have actually changed the file, else the check is meaningless.
if cmp -s "$FILE" "$TMP"; then rm -f "$TMP"; die "mutation did not change $FILE (no-op) -- pick a mutation that hits the guarded code"; fi
cp "$TMP" "$FILE"; rm -f "$TMP"

# 3) re-run: a real guard must now FAIL.
if run_test; then
  printf 'NOT A GUARD: the test still PASSED after mutating %s -- it does not actually assert the guarded behavior.\n' "$FILE"
  printf '  (mutation applied: %s)\n' "${OLD:+replace \"$OLD\"->\"$NEW\"}${DELMATCH:+delete lines matching \"$DELMATCH\"}${DELLINE:+delete line $DELLINE}"
  exit 1
fi

printf 'REAL GUARD: test passed clean and FAILED under mutation of %s -- the guard works.\n' "$FILE"
exit 0
