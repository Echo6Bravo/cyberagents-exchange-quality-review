#!/usr/bin/env bash
# empty-relationship-scan.sh -- HEURISTIC grep for the "empty value silently satisfies a gate"
# bug class (quality-review dimension 1, empty/absent-relationship probe).
#
# This is a SMELL DETECTOR, not a test. It flags code shapes where a missing/empty joined
# value can fall through a filter instead of being excluded -- the pattern behind real
# false-negatives (e.g. `ports = LOOKUP.get(id) or set()` feeding a gate that then treats an
# empty set as "no constraint" rather than "not exposed"). Every hit is a QUESTION to answer by
# reading the code, not a confirmed defect. Zero hits is NOT proof of safety.
#
# Usage:  empty-relationship-scan.sh [path ...]      (defaults to ".")
# Exit:   0 = no smells found; 1 = smells found (review them); 2 = usage error.
set -u
PROG=$(basename "$0")

case "${1-}" in -h|--help) printf 'usage: %s [path ...]\n' "$PROG"; exit 0 ;; esac
[ $# -eq 0 ] && set -- .

# Smell patterns (id : extended-regex). Deliberately narrow to limit false alarms.
# Using a parallel-array-free approach for bash 3.2: newline-separated "id<TAB>regex".
SMELLS='get-or-empty	\.get\([^)]*\)[[:space:]]*(or|\|\|)[[:space:]]*(set\(\)|\[\]|\{\}|new Set\(\)|"")
or-empty-collection	(\|\||[[:space:]]or)[[:space:]]*(new Set\(\)|set\(\))[[:space:]]*$
iterate-get-directly	for[[:space:]].*[[:space:]]in[[:space:]].*\.get\('

SRC_RE='\.(py|js|ts|jsx|tsx|go|rb|sh|java)$'
found_marker=$(mktemp "${TMPDIR:-/tmp}/erscan.XXXXXX") || { echo "$PROG: cannot mktemp" >&2; exit 2; }
: > "$found_marker"

# Enumerate candidate source files (NUL-safe), skipping vendored/generated dirs.
find "$@" \( -name .git -o -name node_modules -o -name dist -o -name build \
            -o -name .venv -o -name vendor \) -prune -o -type f -print0 2>/dev/null \
| while IFS= read -r -d '' f; do
    printf '%s' "$f" | grep -qE "$SRC_RE" || continue
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
  For each hit, read the code and confirm a missing/empty value is EXCLUDED (or surfaced),
  not silently passed through a gate -- dimension 1's empty/absent-relationship probe.
  Heuristic only: zero hits does NOT prove safety; still write a real empty-input test.
EOF
  exit 1
fi
rm -f "$found_marker"
cat <<EOF
$PROG: no empty-fallback smells matched. NOTE: heuristic, not proof --
  still add a real test that feeds a missing/empty relationship and asserts it is excluded.
EOF
exit 0
