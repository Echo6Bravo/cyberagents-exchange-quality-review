#!/usr/bin/env bash
# test_scripts.sh -- tests for the shipped helper scripts in this directory.
# The skill preaches "prove your regression tests are real guards" (dim 11), so its own tools are
# tested here and gated in CI. Portable: bash 3.2+, python3 for the sample targets.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MC="$HERE/mutation-check.sh"
SC="$HERE/empty-relationship-scan.sh"
TS="$HERE/tautology-scan.sh"
pass=0; fail=0
chk(){ if [ "$1" = "$2" ]; then echo "  [PASS] $3"; pass=$((pass+1)); else echo "  [FAIL] $3 (got rc=$1 want $2)"; fail=$((fail+1)); fi; }
# Count matching lines in captured output. rc=1 only proves "at least one hit"; the count is what
# proves every intended shape matched, so must-catch scenarios assert the count too.
cnt(){ printf '%s\n' "$1" | grep -c "$2"; }
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

echo "== tautology-scan.sh =="
# A -- must-catch: the four real shapes from curated-cloud-remediation-generator. A fresh W per
# scenario is load-bearing: sharing one dir would let A's rc=1 mask a negative-control regression.
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/tests"
cat > "$W/tests/test_shapes.py" <<'PY'
assert "AWS docs" in out or not any(r.docs_url for r, _ in unit.pairs)
assert x in y or not precondition
assert foo == bar or not flag
self.assertTrue(a in b or not c)
PY
out=$("$TS" "$W" 2>&1); chk $? 1 "flags assert ... or not (rc=1)"
chk "$(cnt "$out" 'assert-or-not')" 4 "all 4 escape-hatch shapes matched"
echo "$out" | grep -q "test_shapes.py:1" && { echo "  [PASS] file:line"; pass=$((pass+1)); } || { echo "  [FAIL] file:line"; fail=$((fail+1)); }
rm -rf "$W"
# B -- must-not-catch: negative controls, separate dir.
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/tests"
printf 'assert not shutil.which("tofu")\nassert x or y\nassert not (a and b)\nassert "or not" in text\n' > "$W/tests/test_neg.py"
"$TS" "$W" >/dev/null 2>&1; chk $? 0 "negative controls -> rc0"
rm -rf "$W"
# C -- scope control: same defect shape outside a test path must be ignored.
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/src"
printf 'assert x in y or not precondition\n' > "$W/src/app.py"
"$TS" "$W" >/dev/null 2>&1; chk $? 0 "non-test path ignored -> rc0"
rm -rf "$W"
# D -- documented false positives. Locks the header's FP list: a regex "improvement" that changes
# these counts must update the header comment in the same commit.
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/tests"
printf 'assert msg == "enabled or not enabled"\n# assert x in y or not flag\nassert not out.exists() or not (_scripts(out) + _tfs(out))\n' > "$W/tests/test_fp.py"
out=$("$TS" "$W" 2>&1); chk $? 1 "documented FP shapes still fire (rc=1)"
chk "$(cnt "$out" 'assert-or-not')" 3 "exactly the 3 documented FPs"
rm -rf "$W"
# E -- documented blind spot: wrapped `or not` is line-invisible. Asserted so the limitation is a
# tested fact, not just a claim in the header -- if a future rewrite catches it, this test says so.
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/tests"
printf 'assert (\n    "AWS docs" in out\n    or not any(r.docs_url for r in pairs)\n)\n' > "$W/tests/test_wrap.py"
"$TS" "$W" >/dev/null 2>&1; chk $? 0 "known blind spot: wrapped or-not missed"
rm -rf "$W"
# F -- JS/TS: the `|| !precondition` equivalent, plus its negative control.
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/tests"
printf 'expect(out.includes("docs") || !pairs.some(p => p.docsUrl)).toBe(true);\n' > "$W/tests/thing.test.ts"
out=$("$TS" "$W" 2>&1); chk $? 1 "TS || !precondition flagged"
chk "$(cnt "$out" 'expect-or-negation')" 1 "TS smell id"
rm -rf "$W"
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/tests"
printf 'expect(a || b).toBe(true);\nexpect(!x).toBe(true);\n' > "$W/tests/n.test.ts"
"$TS" "$W" >/dev/null 2>&1; chk $? 0 "TS plain || -> rc0"
rm -rf "$W"
# G -- extension filter: a non-source file on a test path must be ignored. Without this the
# SRC_RE guard is unguarded -- deleting it broke no test (found by mutating the scanner).
W=$(mktemp -d "${TMPDIR:-/tmp}/tst.XXXXXX"); mkdir -p "$W/tests"
printf 'ex: assert x in y or not flag\n' > "$W/tests/notes.md"
printf 'assert x in y or not flag\n' > "$W/tests/fixture.txt"
"$TS" "$W" >/dev/null 2>&1; chk $? 0 "non-source ext on test path ignored -> rc0"
rm -rf "$W"
# H -- usage surface, matching the other scanners.
"$TS" --help >/dev/null 2>&1; chk $? 0 "--help -> rc0"

echo ""
echo "helper-script tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
