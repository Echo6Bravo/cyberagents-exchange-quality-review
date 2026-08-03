#!/usr/bin/env bash
# test_scripts.sh -- tests for the shipped helper scripts (mutation-check, empty-relationship-scan).
# The skill preaches "prove your regression tests are real guards" (dim 11), so its own tools are
# tested here and gated in CI. Portable: bash 3.2+, python3 for the sample targets.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MC="$HERE/mutation-check.sh"
SC="$HERE/empty-relationship-scan.sh"
pass=0; fail=0
chk(){ if [ "$1" = "$2" ]; then echo "  [PASS] $3"; pass=$((pass+1)); else echo "  [FAIL] $3 (got rc=$1 want $2)"; fail=$((fail+1)); fi; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "SKIP: $1 not available"; exit 0; }; }
need python3

echo "== mutation-check.sh =="
W=$(mktemp -d "${TMPDIR:-/tmp}/mct.XXXXXX")
printf 'def classify(x):\n    return "keep" if x > 5 else "drop"\n' > "$W/mod.py"
printf 'import mod\nassert mod.classify(10)=="keep"\nassert mod.classify(1)=="drop"\nprint("ok")\n' > "$W/test_real.py"
printf 'import mod\nassert hasattr(mod,"classify")\nprint("ok")\n' > "$W/test_taut.py"

"$MC" --test "cd $W && python3 test_real.py" --file "$W/mod.py" --old "> 5" --new "> 999" >/dev/null 2>&1
chk $? 0 "real guard detected (rc=0)"
"$MC" --test "cd $W && python3 test_taut.py" --file "$W/mod.py" --old "> 5" --new "> 999" >/dev/null 2>&1
chk $? 1 "tautology detected (rc=1)"
grep -q "> 5" "$W/mod.py" && { echo "  [PASS] file restored"; pass=$((pass+1)); } || { echo "  [FAIL] not restored"; fail=$((fail+1)); }
"$MC" --test "cd $W && python3 test_real.py" --file "$W/mod.py" --old "NONEXISTENT" --new "x" >/dev/null 2>&1
chk $? 2 "missing --old -> rc=2"
printf 'assert False\n' > "$W/test_broken.py"
"$MC" --test "cd $W && python3 test_broken.py" --file "$W/mod.py" --old "> 5" --new "> 9" >/dev/null 2>&1
chk $? 2 "baseline not green -> rc=2"
"$MC" --test "cd $W && python3 test_real.py" --file "$W/mod.py" --delete-match 'return' >/dev/null 2>&1
chk $? 0 "delete-match (real guard rc=0)"
"$MC" --test x >/dev/null 2>&1; chk $? 2 "missing --file -> rc=2"
"$MC" --file "$W/mod.py" >/dev/null 2>&1; chk $? 2 "missing --test -> rc=2"
"$MC" --test x --file "$W/mod.py" --old a --new b --delete-line 1 >/dev/null 2>&1; chk $? 2 "two modes -> rc=2"
rm -rf "$W"

echo "== empty-relationship-scan.sh =="
W=$(mktemp -d "${TMPDIR:-/tmp}/sct.XXXXXX")
printf 'def r(rows,PORTS):\n    for x in rows:\n        vp = PORTS.get(x) or set()\n' > "$W/risky.py"
out=$("$SC" "$W" 2>&1); chk $? 1 "flags .get() or set()"
echo "$out" | grep -q "get-or-empty" && { echo "  [PASS] smell id"; pass=$((pass+1)); } || { echo "  [FAIL] smell id"; fail=$((fail+1)); }
echo "$out" | grep -q "risky.py:3" && { echo "  [PASS] file:line"; pass=$((pass+1)); } || { echo "  [FAIL] file:line"; fail=$((fail+1)); }
rm -rf "$W"
W=$(mktemp -d "${TMPDIR:-/tmp}/sct.XXXXXX")
printf 'def r(rows,PORTS):\n    for x in rows:\n        vp=PORTS.get(x)\n        if not vp: continue\n' > "$W/clean.py"
"$SC" "$W" >/dev/null 2>&1; chk $? 0 "clean code -> rc0"
rm -rf "$W"
W=$(mktemp -d "${TMPDIR:-/tmp}/sct.XXXXXX")
printf 'ex: x = d.get(k) or set()\n' > "$W/notes.md"
"$SC" "$W" >/dev/null 2>&1; chk $? 0 ".md ignored -> rc0"
rm -rf "$W"
W=$(mktemp -d "${TMPDIR:-/tmp}/sct.XXXXXX")
printf 'const vp = portMap.get(id) || new Set();\n' > "$W/x.js"
"$SC" "$W" >/dev/null 2>&1; chk $? 1 "JS || new Set() flagged"
rm -rf "$W"

echo ""
echo "helper-script tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
