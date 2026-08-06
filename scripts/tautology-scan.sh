#!/usr/bin/env bash
# tautology-scan.sh -- HEURISTIC grep for the "assertion that cannot fail" bug class
# (quality-review dimension 11, prove-the-regression-test-is-a-real-guard probe).
#
# This is a SMELL DETECTOR, not a test. It flags assertions carrying an `or not <precondition>`
# escape hatch: when the precondition is false in the fixture, the right-hand side is always true,
# the real claim on the left is never evaluated, and the test asserts nothing while reading as
# coverage. `mutation-check.sh` cannot find these -- no mutation to the file under test changes the
# outcome. Every hit is a QUESTION to answer by reading the code, not a confirmed defect.
# Zero hits is NOT proof of safety.
#
# Scope: TEST files only (that is where the shape matters), by path convention -- tests/, spec/,
# test_*.*, *_test.*, *.test.[jt]s(x), *.spec.[jt]s(x).
#
# KNOWN FALSE POSITIVES (measured, expected; triage by reading. Do NOT "fix" the regex without
# updating this list and the matching tests in test_scripts.sh -- they are locked together):
#   * prose inside a string literal, e.g. `assert msg == "enabled or not enabled"`
#     (note `assert "or not" in text` does NOT fire -- the quote before `or` fails the pattern)
#   * a commented-out assertion, e.g. `# assert x in y or not flag`
#   * a genuine two-branch claim, e.g. `assert not out.exists() or not _files(out)` -- both halves
#     are real claims. Still worth the look: confirm the right half is actually reachable.
#
# KNOWN BLIND SPOTS (this grep is line-based and will MISS these):
#   * the black/prettier-formatted form where `or not` wraps onto its own continuation line, so no
#     single line contains both `assert` and `or not`
#   * assertions over a DERIVED property (@property, cached_property, getter, serializer formula),
#     which re-implement the derivation and pass on every input. Not greppable -- it needs a human
#     to answer "is this field authored data or computed?". See dimension 11 prose.
#   * Python/JS shapes only. Go/Java/Ruby test idioms are not matched.
#
# Usage:  tautology-scan.sh [path ...]      (defaults to ".")
# Exit:   0 = no smells found; 1 = smells found (review them); 2 = usage error.
set -u
PROG=$(basename "$0")

case "${1-}" in -h|--help) printf 'usage: %s [path ...]\n' "$PROG"; exit 0 ;; esac
[ $# -eq 0 ] && set -- .

# Smell patterns (id : extended-regex). Deliberately narrow to limit false alarms.
# Using a parallel-array-free approach for bash 3.2: newline-separated "id<TAB>regex".
# `assert[[:alnum:]_]*` covers assert, assertTrue, assertFalse, assertEqual, assertIn, ...
SMELLS='assert-or-not	(^|[^[:alnum:]_])assert[[:alnum:]_]*[[:space:](].*[[:space:])]or[[:space:]]+not[[:space:](]
expect-or-negation	(^|[^[:alnum:]_])(expect|assert)[[:alnum:]_]*\(.*\|\|[[:space:]]*!'

TEST_RE='(^|/)(tests?|spec)/|(^|/)test_[^/]*$|_test\.[a-z]+$|\.(test|spec)\.[jt]sx?$'
SRC_RE='\.(py|js|ts|jsx|tsx|rb)$'
found_marker=$(mktemp "${TMPDIR:-/tmp}/tautscan.XXXXXX") || { echo "$PROG: cannot mktemp" >&2; exit 2; }
: > "$found_marker"

# Enumerate candidate test files (NUL-safe), skipping vendored/generated dirs.
find "$@" \( -name .git -o -name node_modules -o -name dist -o -name build \
            -o -name .venv -o -name vendor \) -prune -o -type f -print0 2>/dev/null \
| while IFS= read -r -d '' f; do
    printf '%s' "$f" | grep -qE "$SRC_RE" || continue
    printf '%s' "$f" | grep -qE "$TEST_RE" || continue
    # iterate smell patterns
    printf '%s\n' "$SMELLS" | while IFS="$(printf '\t')" read -r id rx; do
      [ -n "$id" ] || continue
      hits=$(grep -nEI "$rx" "$f" 2>/dev/null) || continue
      [ -n "$hits" ] || continue
      echo 1 >> "$found_marker"
      printf '%s\n' "$hits" | while IFS= read -r line; do
        printf '%s:%s  [%s]\n' "$f" "${line%%:*}" "$id"
      done
    done
  done

echo ""
if [ -s "$found_marker" ]; then
  rm -f "$found_marker"
  cat <<EOF
$PROG: smells found above. Each is a QUESTION, not a confirmed bug.
  For each hit, ask: is the right-hand side of the \`or not\` FALSE in the fixture? If so the
  left-hand claim never runs -- the test passes while asserting nothing. Assert the precondition
  separately, or use a fixture where it holds -- dimension 11's real-guard probe.
  Heuristic only: zero hits does NOT prove the suite has no tautologies; multi-line and
  derived-property shapes are invisible to this grep (see header).
EOF
  exit 1
fi
rm -f "$found_marker"
cat <<EOF
$PROG: no escape-hatch assertion smells matched. NOTE: heuristic, not proof --
  line-based grep misses wrapped \`or not\` continuations and assertions over derived
  properties. Still mutate a real guard (scripts/mutation-check.sh) to prove it can fail.
EOF
exit 0
