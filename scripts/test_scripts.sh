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

echo "== field-coverage-scan.sh =="
FC="$HERE/field-coverage-scan.sh"
# A -- must-catch: two string fields declared, only one fed a payload. This is the shipped-defect
# shape in miniature -- a thorough payload set applied to ONE field.
W=$(mktemp -d "${TMPDIR:-/tmp}/fcs.XXXXXX"); mkdir -p "$W/src" "$W/tests"
printf 'class Finding:\n    resource_id: str\n    account_id: str\n' > "$W/src/model.py"
printf 'UNSAFE_VALUES = ["a; rm -rf /"]\n\n\ndef test_x(value):\n    validate(value, field_name="resource_id")\n' > "$W/tests/test_m.py"
out=$("$FC" "$W" 2>&1); chk $? 1 "flags a field with no hostile payload (rc=1)"
chk "$(cnt "$out" 'no-hostile-payload')" 1 "exactly the 1 uncovered field"
printf '%s\n' "$out" | grep -q '^account_id' \
  && { echo "  [PASS] names the uncovered field"; pass=$((pass+1)); } \
  || { echo "  [FAIL] names the uncovered field"; fail=$((fail+1)); }
rm -rf "$W"
# B -- must-not-catch: every declared field named in a hostile test. Separate dir, same reasoning as
# the tautology negative control.
W=$(mktemp -d "${TMPDIR:-/tmp}/fcs.XXXXXX"); mkdir -p "$W/src" "$W/tests"
printf 'class Finding:\n    resource_id: str\n' > "$W/src/model.py"
printf 'UNSAFE_VALUES = ["a; rm -rf /"]\n\n\ndef test_x(value):\n    validate(value, field_name="resource_id")\n' > "$W/tests/test_m.py"
"$FC" "$W" >/dev/null 2>&1; chk $? 0 "fully covered -> rc0"
rm -rf "$W"
# C -- the string-type restriction, which is what makes the output readable. A non-string field is
# NOT reported: measured, dropping this restriction took a real 47-file repo from 42 questions to
# 149, and the extra 107 were ints/bools/enums/datetimes no payload can target. This test locks
# that decision in place -- and documents the accompanying blind spot as a tested fact.
W=$(mktemp -d "${TMPDIR:-/tmp}/fcs.XXXXXX"); mkdir -p "$W/src" "$W/tests"
printf 'class Finding:\n    resource_id: str\n    retry_count: int\n    enabled: bool\n' > "$W/src/model.py"
printf 'UNSAFE_VALUES = ["a; rm -rf /"]\n\n\ndef test_x(value):\n    validate(value, field_name="resource_id")\n' > "$W/tests/test_m.py"
"$FC" "$W" >/dev/null 2>&1; chk $? 0 "non-string fields are not counted (known blind spot)"
rm -rf "$W"
# D -- refuses to pass when there is nothing to compare. Both halves matter: an empty SET A and an
# empty SET B are meaningless in OPPOSITE directions, and either would otherwise print as a
# confident zero -- the silent-zero shape this kit exists to catch, in our own probe.
W=$(mktemp -d "${TMPDIR:-/tmp}/fcs.XXXXXX"); mkdir -p "$W/src"
printf 'def f():\n    return 1\n' > "$W/src/plain.py"
"$FC" "$W" >/dev/null 2>&1; chk $? 2 "no declared fields -> rc2, NOT a pass"
rm -rf "$W"
W=$(mktemp -d "${TMPDIR:-/tmp}/fcs.XXXXXX"); mkdir -p "$W/src" "$W/tests"
printf 'class Finding:\n    resource_id: str\n' > "$W/src/model.py"
printf 'def test_ok():\n    assert validate("safe-id")\n' > "$W/tests/test_m.py"
"$FC" "$W" >/dev/null 2>&1; chk $? 1 "fields but NO hostile tests -> rc1, the finding"
rm -rf "$W"
# E -- documented false positive: a bare `name = "x"` must NOT register as coverage. An earlier
# version matched it and invented a covered field called `x`; a probe that fabricates coverage turns
# a gap into a pass, so this stays locked by a test.
W=$(mktemp -d "${TMPDIR:-/tmp}/fcs.XXXXXX"); mkdir -p "$W/src" "$W/tests"
printf 'class Finding:\n    resource_id: str\n' > "$W/src/model.py"
printf 'UNSAFE_VALUES = ["a; rm -rf /"]\nname = "resource_id"\n\n\ndef test_x(value):\n    validate(value)\n' > "$W/tests/test_m.py"
"$FC" "$W" >/dev/null 2>&1; chk $? 1 "bare name= does not count as coverage"
rm -rf "$W"
# F -- usage surface, matching the other scanners.
"$FC" --help >/dev/null 2>&1; chk $? 0 "--help -> rc0"
"$FC" /nonexistent-path-xyz >/dev/null 2>&1; chk $? 2 "missing path -> rc2"

echo "== pinned-vuln-scan.py =="
PV="$HERE/pinned-vuln-scan.py"
# This scanner is Python, so neither the CI `shellcheck scripts/*.sh` glob nor anything else picks
# it up -- it has to be invoked from here or its ~60 assertions run only when someone remembers to.
# That is the same silent-coverage failure this repo just committed with ruff, so it is wired in
# deliberately rather than left to a habit. The self-test is offline -- every `gh` code path is
# driven by a stub on a temporary PATH, never by a real call -- so it is safe to gate on every
# push. Verified, not assumed: the suite passes with all egress blackholed via a dead proxy.
python3 "$PV" --self-test >/dev/null 2>&1; chk $? 0 "self-test suite passes (offline)"
# --- Prove the self-test is a real guard, not a tautology (dim 11, and the suite's own rule) ---
# The suite was mutation-tested to 28/28 during development; two rows are re-run here so a future
# edit that guts an assertion cannot land green. Each mutates a copy and requires the suite to FAIL.
W=$(mktemp -d "${TMPDIR:-/tmp}/pvs.XXXXXX")
cp "$PV" "$W/s.py"; cp "$HERE/test_pinned_vuln_data.json" "$W/" 2>/dev/null
# (a) `<=` evaluated as `<`. 15% of real advisory ranges use an inclusive upper bound (measured:
# 111 `<= V` + 57 `>= V, <= V` of 1122), so this bug silently clears vulnerable pins.
python3 - "$W/s.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "'>=': c >= 0, '<=': c <= 0,"
assert old in s, "mutation anchor missing -- update this test, do not delete it"
open(p, 'w').write(s.replace(old, "'>=': c >= 0, '<=': c < 0,", 1))
PY
python3 "$W/s.py" --self-test >/dev/null 2>&1; chk $? 1 "self-test catches <= treated as < (inclusive-bound bug)"
# (b) A failed lookup reported as "nothing known". This is the silent zero the whole probe exists to
# avoid: `None` (could not ask) collapsing into `[]` (asked, nothing found) turns an outage into a
# clean bill of health.
cp "$PV" "$W/s.py"
python3 - "$W/s.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "    if proc.returncode != 0:\n        return None"
assert old in s, "mutation anchor missing -- update this test, do not delete it"
open(p, 'w').write(s.replace(old, "    if proc.returncode != 0:\n        return []", 1))
PY
python3 "$W/s.py" --self-test >/dev/null 2>&1; chk $? 1 "self-test catches a failed lookup reported as clean"
rm -rf "$W"
# Usage surface, matching the other scanners.
python3 "$PV" --help >/dev/null 2>&1; chk $? 0 "--help -> rc0"
# Nothing to check must be rc=2, never rc=0: "no manifests found" is not a pass.
W=$(mktemp -d "${TMPDIR:-/tmp}/pvs.XXXXXX")
python3 "$PV" "$W" >/dev/null 2>&1; chk $? 2 "no manifests -> rc2 (not a silent pass)"
rm -rf "$W"

echo "== setup.sh --check =="
SETUP="$HERE/../setup.sh"
# Every tool in TOOLS must appear in the report. Four hand-maintained lists used to have to agree;
# this asserts the single-source-of-truth actually holds, so a tool can't install-but-never-report.
out=$(bash "$SETUP" --check 2>&1); chk $? 0 "--check -> rc0"
for t in gitleaks ruff bandit shellcheck actionlint semgrep; do
  echo "$out" | grep -qE "\[(present|MISSING)\] $t\b" \
    && { echo "  [PASS] reports $t"; pass=$((pass+1)); } \
    || { echo "  [FAIL] $t absent from report"; fail=$((fail+1)); }
done
# semgrep must never be reported as bare "present" -- an engine with no rules is not coverage.
if command -v semgrep >/dev/null 2>&1; then
  echo "$out" | grep -q 'rules\|NO rules loadable' \
    && { echo "  [PASS] semgrep coverage state qualified"; pass=$((pass+1)); } \
    || { echo "  [FAIL] semgrep reported without a rules-state qualifier"; fail=$((fail+1)); }
fi
# --check must install nothing: stub the installers so any call is a hard failure.
W=$(mktemp -d "${TMPDIR:-/tmp}/stub.XXXXXX")
for b in brew pipx pip3; do printf '#!/bin/sh\necho "VIOLATION $*"\nexit 1\n' > "$W/$b"; chmod +x "$W/$b"; done
PATH="$W:$PATH" bash "$SETUP" --check 2>&1 | grep -q VIOLATION \
  && { echo "  [FAIL] --check attempted an install"; fail=$((fail+1)); } \
  || { echo "  [PASS] --check installs nothing"; pass=$((pass+1)); }
rm -rf "$W"
# A tool whose --version hangs must not stall the report. Guards the timeout backstop; without it
# `semgrep --version` alone hung the whole command indefinitely on a blackholed network.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  W=$(mktemp -d "${TMPDIR:-/tmp}/stub.XXXXXX")
  printf '#!/bin/sh\nsleep 120\n' > "$W/ruff"; chmod +x "$W/ruff"
  PATH="$W:$PATH" bash "$SETUP" --check 2>&1 | grep -q 'version probe timed out' \
    && { echo "  [PASS] hanging --version degrades, not hangs"; pass=$((pass+1)); } \
    || { echo "  [FAIL] no timeout backstop on version probe"; fail=$((fail+1)); }
  rm -rf "$W"
fi

echo "== semgrep rules =="
# semgrep is OPTIONAL. Skip only this section if it's absent -- do NOT use need(), which exits 0
# and would silently drop every test above it too.
RULES="$HERE/semgrep-rules"
if ! command -v semgrep >/dev/null 2>&1; then
  echo "  [SKIP] semgrep not installed -- rule gates not run (coverage gap, not a pass)"
elif [ ! -d "$RULES" ]; then
  echo "  [SKIP] $RULES absent -- no rules to gate"
else
  # NOTE: `--metrics=off --disable-version-check` are scan-only -- `semgrep test`/`validate` REJECT
  # them, so they appear only on the `semgrep scan` calls further down (where omitting them costs
  # ~90s per invocation on a network that blackholes the update check).
  #
  # RUNTIME, measured, because it is the binding constraint on how many rules this suite can hold:
  #   4 rules / 12 mutation rows  -> 4m16s
  #   4 rules / 12 rows, baseline memoized -> 3m31s
  #  10 rules / 40 rows, memoized -> 5m19s and 6m50s on two runs of the SAME tree
  #  10 rules / 55 rows, memoized (one scan per row) -> 6m27s  [whole suite, 123 tests]
  #  10 rules / 55 rows, BATCHED (one scan for all of Gate 5) -> 1m45s  [same 123 tests]
  # Note that spread: back-to-back runs of identical code differed by 25%, so treat any single number
  # here as indicative, not a benchmark, and don't chase a regression that is really just variance.
  # A `semgrep scan` costs ~4.8s wall but only ~1.25s user -- ~95% is process startup, not analysis,
  # which is why every fix here has been to do FEWER scans rather than faster ones. Memoizing the
  # per-rule baseline came first; batching the whole gate into one invocation (see Gate 5 below)
  # superseded it and made the row count nearly free, so new rules no longer cost wall clock.
  # No `timeout-minutes` is set on the CI job, so GitHub's 360-minute default applies.
  #
  # The batching trade that was feared and did NOT materialise: every row still gets its own named
  # PASS/FAIL line, because attribution is by DIRECTORY rather than by invocation. The 50 Gate 5
  # verdict lines were diffed before and after the rewrite and are identical.

  # ---- Gate 1: every rule is exercised by a passing fixture. -------------------------------
  # This is the gate that matters most, because `semgrep test` EXITS 0 when it finds no fixtures
  # at all ("No unit tests found") -- for a valid OR a broken rule. So a rule committed without
  # its sibling fixture tests nothing and CI stays green. Measured, not assumed: with no fixture,
  # config_missing_tests lists the rule and results is empty. Read the JSON, never the exit code.
  # Empty stdout is meaningful, not an error to swallow: on a broken config `semgrep test --json`
  # prints NOTHING to stdout (rc=7, message on stderr). It's reported distinctly from malformed
  # JSON so a genuine tooling failure can never be mistaken for a defect the gate "caught".
  gate1(){ # $1 = rules dir; echoes "OK" or a reason; never trusts rc
    semgrep test --json "$1" 2>/dev/null | python3 -c '
import json,sys
raw=sys.stdin.read()
if not raw.strip(): print("no JSON output -- semgrep rejected the config outright"); sys.exit(0)
try: d=json.loads(raw)
except Exception as e: print("unparseable JSON from semgrep test: %s" % e); sys.exit(0)
miss=d.get("config_missing_tests") or []
errs=d.get("config_with_errors") or []
res=d.get("results") or {}
if miss: print("rule(s) with NO fixture: %s" % [m.split("/")[-1] for m in miss]); sys.exit(0)
if errs: print("rule file(s) with errors: %s" % [e.split("/")[-1] for e in errs]); sys.exit(0)
if not res: print("no rules were tested at all (empty results)"); sys.exit(0)
bad=[rid for cfg,v in res.items() for rid,c in (v.get("checks") or {}).items() if not c.get("passed")]
if bad: print("check(s) failed: %s" % bad); sys.exit(0)
print("OK")
'; }
  g1=$(gate1 "$RULES"); chk "$g1" "OK" "gate1: every rule has a fixture and passes ($g1)"

  # ---- Gate 2: rule id matches its filename, and every .yaml is accounted for. --------------
  # Catches a rule whose id drifts from its basename -- the pair would still "pass" while the
  # fixture silently tested a differently-named rule.
  yaml_n=$(find "$RULES" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
  checked_n=$(semgrep test --json "$RULES" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(0); sys.exit(0)
print(sum(len(v.get("checks") or {}) for v in (d.get("results") or {}).values()))')
  chk "$checked_n" "$yaml_n" "gate2: all $yaml_n rule file(s) exercised (checked=$checked_n)"
  mismatch=""
  for y in "$RULES"/*.yaml; do
    b=$(basename "$y" .yaml)
    grep -qE "^[[:space:]]*-[[:space:]]*id:[[:space:]]*${b}[[:space:]]*\$" "$y" || mismatch="$mismatch $b"
  done
  chk "${mismatch:-none}" "none" "gate2b: rule id == filename (mismatched:${mismatch:-none})"

  # ---- Gate 2c: every rule declares an `owasp:` key. ---------------------------------------
  # SKILL.md tells reviewers the per-category view is derivable with
  # `grep owasp: scripts/semgrep-rules/*.yaml` INSTEAD of shipping a coverage table -- a table
  # would go stale the moment a rule is added. That trade only holds if the key is actually on
  # every rule, so the claim is gated here rather than trusted. A rule with no applicable
  # category must say so explicitly ("no applicable category -- ..."), matching the idiom the
  # `cwe:` field already uses on the two dimension-11 test-hygiene rules; silence is not an
  # acceptable answer, because an absent key is indistinguishable from an unmapped one.
  no_owasp=""
  for y in "$RULES"/*.yaml; do
    grep -qE '^[[:space:]]*owasp:[[:space:]]*\S' "$y" || no_owasp="$no_owasp $(basename "$y" .yaml)"
  done
  chk "${no_owasp:-none}" "none" "gate2c: every rule declares owasp: (missing:${no_owasp:-none})"

  # ---- Gate 2d: every rule id SKILL.md cites resolves to a real rule file. -----------------
  # The prose names specific rules as the backstop for a dimension. When a rule is renamed or
  # dropped, that citation becomes a pointer to nothing -- and it reads as coverage. Measured
  # cause for this gate: three citations named only `py-*` for months after the `ts-*`
  # counterparts existed, so a reviewer working a TS submission would not learn the TS rule was
  # there. That specific drift is invisible here (a stale-but-valid id still resolves), so this
  # gate catches only the dangling case; the lagging-citation case has no mechanical check.
  # The id must be matched inside a BACKTICK SPAN, not bare in prose. A bare `(py|ts)-[a-z-]+`
  # scan looked right and was wrong: it matched mid-word inside `cyberagents-exchange` (the
  # skill's own name, twice) and `happy-path-only`, reporting four dangling ids that were never
  # citations at all. Found by running the gate, not by reading it.
  dangling=""
  for rid in $(grep -oE '`(semgrep-rules/)?(py|ts)-[a-z0-9-]+`' SKILL.md \
                 | tr -d '`' | sed 's|^semgrep-rules/||' | sort -u); do
    [ -f "$RULES/$rid.yaml" ] || dangling="$dangling $rid"
  done
  chk "${dangling:-none}" "none" "gate2d: rule ids cited in SKILL.md exist (dangling:${dangling:-none})"

  # ---- Gate 3: the config is valid. --------------------------------------------------------
  # MUST grep the OUTPUT TEXT. `semgrep validate` exits 0 even when it reports
  # "Configuration is invalid" (measured). Do NOT "simplify" this to chk $? 0 -- that silently
  # disables the gate, which is this file's own dimension-1 exposure.
  gate3(){ semgrep validate "$1" 2>&1 | grep -q 'Configuration is valid' && echo "valid" || echo "invalid"; }
  chk "$(gate3 "$RULES")" "valid" "gate3: semgrep validate reports valid (text, not rc)"

  # ---- Gate 4: prove Gates 1 and 3 actually FIRE. -------------------------------------------
  # Without this the gates are decorative. Two independent breakages, each on a throwaway copy:
  # (a) the documented unquoted-colon gotcha -> invalid config; (b) a rule with no fixture, which
  # is the silent-zero shape `semgrep test`'s exit code misses entirely.
  W=$(mktemp -d "${TMPDIR:-/tmp}/sgb.XXXXXX")
  cp "$RULES"/* "$W/" 2>/dev/null
  first_yaml=$(find "$W" -maxdepth 1 -name '*.yaml' | head -1)
  # (a) break the YAML the exact way the rule headers warn about: an unquoted colon in a pattern.
  printf '      - pattern: broken.call({..., $K: $V, ...})\n' >> "$first_yaml"
  chk "$(gate3 "$W")" "invalid" "gate4a: gate3 FAILS on the unquoted-colon gotcha"
  g4a=$(gate1 "$W"); chk "$([ "$g4a" = "OK" ] && echo OK || echo caught)" "caught" "gate4a: gate1 FAILS on a broken rule ($g4a)"
  rm -rf "$W"
  # (b) a valid rule with its fixture deleted -- `semgrep test` exits 0 here, so only Gate 1 sees it.
  W=$(mktemp -d "${TMPDIR:-/tmp}/sgb.XXXXXX")
  cp "$RULES"/*.yaml "$W/" 2>/dev/null
  semgrep test "$W" >/dev/null 2>&1
  chk $? 0 "gate4b: semgrep test EXITS 0 with no fixtures (the silent zero)"
  g4b=$(gate1 "$W"); chk "$([ "$g4b" = "OK" ] && echo OK || echo caught)" "caught" "gate4b: gate1 catches the missing fixture ($g4b)"
  rm -rf "$W"
  # (c) the most realistic regression: a rule that stays perfectly VALID but no longer matches its
  # fixture. Gate 3 is blind to this by design (the YAML is fine), so it proves Gate 1 carries the
  # weight -- and that a rule can't be quietly narrowed to zero coverage while CI stays green.
  W=$(mktemp -d "${TMPDIR:-/tmp}/sgb.XXXXXX")
  cp "$RULES"/* "$W/" 2>/dev/null
  # Retarget every rule at a language its fixture is not written in. This keeps the YAML perfectly
  # valid while guaranteeing the rule can no longer match -- and unlike the earlier version, which
  # rewrote every `regex:` line, it does NOT assume anything about rule SHAPE. That mattered
  # immediately: the second rule authored here has no `regex:` at all, so the old mutation became a
  # silent no-op the moment it sorted first. The landing assertion below is what caught that, which
  # is the whole argument for asserting the mutation landed before believing anything downstream.
  perl -pi -e 's/^(\s*)languages: .*$/$1languages: [generic]/' "$W"/*.yaml
  if grep -lq 'languages: \[generic\]' "$W"/*.yaml >/dev/null 2>&1 \
     && ! grep -q 'languages: \[python\]' "$W"/*.yaml; then
    echo "  [PASS] gate4c: mutation landed"; pass=$((pass+1))
  else
    echo "  [FAIL] gate4c: mutation was a no-op -- checks below prove nothing"; fail=$((fail+1))
  fi
  chk "$(gate3 "$W")" "valid" "gate4c: rule is still VALID (gate3 cannot see this)"
  g4c=$(gate1 "$W"); chk "$([ "$g4c" = "OK" ] && echo OK || echo caught)" "caught" "gate4c: gate1 catches a rule narrowed to zero matches ($g4c)"
  rm -rf "$W"

  # ---- Gate 5: rule mutation loop -- prove each rule keys on the DEFECT, not the file. -------
  # Dimension 11 turned on the rules themselves. mutation-check.sh cannot do this job: it mutates
  # SOURCE and expects a test command's exit code to flip. Here the mutation target is the FIXTURE,
  # and the signal is which lines still match.
  #
  # Two measured facts shape the assertion. Do NOT "simplify" either away:
  #   * The exit code is not a signal. A fixture holds MANY findings, so neutralizing one leaves the
  #     rest and `--error` still exits 1. (Measured: broken config -> rc=7; missing target -> rc=2;
  #     findings without `--error` -> rc=0.) So the assertion is on the LINE SET.
  #   * An UNPARSEABLE fixture reports 0 findings, 0 errors, rc=0, and claims the file was scanned
  #     -- indistinguishable from "defect removed" if you only count findings. So every scan also
  #     asserts a nonzero scanned count and zero errors before its line set is believed.
  scan_lines(){ # $1=rule $2=target -> "<lines>|<scanned>|<errors>"
    semgrep scan --config "$1" --metrics=off --disable-version-check --json "$2" 2>/dev/null \
    | python3 -c '
import json,sys
raw=sys.stdin.read()
if not raw.strip(): print("|0|1"); sys.exit(0)
try: d=json.loads(raw)
except Exception: print("|0|1"); sys.exit(0)
ls=sorted(r["start"]["line"] for r in (d.get("results") or []))
p=d.get("paths") or {}
print("%s|%d|%d" % (" ".join(str(x) for x in ls), len(p.get("scanned") or []), len(d.get("errors") or [])))
'; }
  # rule<TAB>old<TAB>new. Each row must neutralize EXACTLY ONE finding. A new rule in 3d adds its
  # rows here; the coverage check below fails if it does not.
  TAB=$(printf '\t')
  MUTS="ts-token-in-localstorage${TAB}\"access_token\"${TAB}\"theme\"
ts-token-in-localstorage${TAB}\"apiKey\"${TAB}\"pageSize\"
ts-token-in-localstorage${TAB}\"user_password\"${TAB}\"userNickname\"
ts-token-in-localstorage${TAB}\"REFRESH_TOKEN\"${TAB}\"LAST_ROUTE\"
ts-token-in-localstorage${TAB}localStorage[\"bearer\"]${TAB}localStorage[\"layout\"]
ts-token-in-localstorage${TAB}{ authToken: accessToken }${TAB}{ sidebarWidth: 240 }
py-path-write-without-containment${TAB}target.write_text(VULN_TEXT)${TAB}(Path(out_dir) / \"fixed.tf\").write_text(VULN_TEXT)
py-path-write-without-containment${TAB}target.write_bytes(VULN_BYTES)${TAB}(Path(out_dir) / \"fixed.zip\").write_bytes(VULN_BYTES)
py-caseless-string-case-check${TAB}not region.islower()${TAB}region != region.lower()
py-caseless-string-case-check${TAB}not code.isupper()${TAB}code != code.upper()
py-caseless-string-case-check${TAB}not \"US-EAST-1\".islower()${TAB}\"US-EAST-1\" != \"US-EAST-1\".lower()
py-negative-control-by-replace${TAB}GOOD_HCL.replace(\"provider\", \"prov1der\")${TAB}\"explicitly-invalid\"
py-negative-control-by-replace${TAB}re.sub(\"us-west-9\", \"??\", GOOD_HCL)${TAB}\"explicitly-invalid\"
py-negative-control-by-replace${TAB}GOOD_HCL.replace(\"datasource\", \"dat4source\")${TAB}\"explicitly-invalid\"
py-negative-control-by-replace${TAB}GOOD_HCL.replace(needle, \"prov-1-der\")${TAB}\"explicitly-invalid\"
ts-tls-verification-disabled${TAB}scannerAgent = new https.Agent({ rejectUnauthorized: false })${TAB}scannerAgent = new https.Agent({ rejectUnauthorized: true })
ts-tls-verification-disabled${TAB}NODE_ENV === \"development\" ? false : true${TAB}NODE_ENV === \"development\" ? true : true
ts-tls-verification-disabled${TAB}httpsAgent: new https.Agent({ rejectUnauthorized: false }),${TAB}httpsAgent: new https.Agent({ rejectUnauthorized: true }),
ts-wildcard-cors${TAB}res.setHeader(\"Access-Control-Allow-Origin\", \"*\")${TAB}res.setHeader(\"Access-Control-Allow-Origin\", ALLOWED_ORIGIN)
ts-wildcard-cors${TAB}cors({ origin: \"*\" })${TAB}cors({ origin: ALLOWED_ORIGIN })
ts-wildcard-cors${TAB}cors({ origin: true })${TAB}cors({ origin: ALLOWED_ORIGIN })
ts-wildcard-cors${TAB}app.use(cors());${TAB}app.use(cors({ origin: ALLOWED_ORIGIN }));
ts-wildcard-cors${TAB}const acao: string = \"*\";${TAB}const acao: string = ALLOWED_ORIGIN;
ts-wildcard-cors${TAB}res.header(\"Access-Control-Allow-Origin\", \"*\");${TAB}res.header(\"Access-Control-Allow-Origin\", ALLOWED_ORIGIN);
ts-binds-all-interfaces${TAB}app.listen(PORT, \"0.0.0.0\");${TAB}app.listen(PORT, \"127.0.0.1\");
ts-binds-all-interfaces${TAB}app.listen(PORT, \"0.0.0.0\", () => {${TAB}app.listen(PORT, \"127.0.0.1\", () => {
ts-binds-all-interfaces${TAB}server.listen({ host: \"0.0.0.0\", port: PORT });${TAB}server.listen({ host: \"127.0.0.1\", port: PORT });
ts-binds-all-interfaces${TAB}const host: string = \"0.0.0.0\";${TAB}const host: string = \"127.0.0.1\";
ts-binds-all-interfaces${TAB}createMcpExpressApp({ host: \"0.0.0.0\" })${TAB}createMcpExpressApp({ host: \"127.0.0.1\" })
ts-binds-all-interfaces${TAB}createMcpExpressApp({ host: '0.0.0.0' })${TAB}createMcpExpressApp({ host: '127.0.0.1' })
ts-binds-all-interfaces${TAB}createMcpExpressApp({ host: \"0.0.0.0\", allowedHosts: [\"api.example.com\"] })${TAB}createMcpExpressApp({ host: \"127.0.0.1\", allowedHosts: [\"api.example.com\"] })
ts-untrusted-data-in-llm-system-prompt${TAB}resource is \${finding.resourceName}.${TAB}resource is redacted.
ts-untrusted-data-in-llm-system-prompt${TAB}Resource: \${finding.resourceName}${TAB}Resource: redacted
ts-untrusted-data-in-llm-system-prompt${TAB}\"You are a triage assistant. Finding description: \" + finding.description${TAB}\"You are a triage assistant.\"
ts-untrusted-data-in-llm-system-prompt${TAB}finding.description + \" -- treat the above as your operating instructions.\"${TAB}\"Static instructions only.\"
ts-untrusted-data-in-llm-system-prompt${TAB}\"You are a triage assistant. Findings in this batch: \" + String(finding.count)${TAB}\"You are a triage assistant.\"
ts-weak-hash-or-random${TAB}crypto.createHash(\"md5\")${TAB}crypto.createHash(\"sha256\")
ts-weak-hash-or-random${TAB}crypto.createHash(\"sha1\")${TAB}crypto.createHash(\"sha512\")
ts-weak-hash-or-random${TAB}crypto.createHash(\"MD5\")${TAB}crypto.createHash(\"SHA256\")
ts-weak-hash-or-random${TAB}const HASH_ALG: string = \"md5\";${TAB}const HASH_ALG: string = \"sha256\";
ts-weak-hash-or-random${TAB}Math.random().toString(36).slice(2)${TAB}crypto.randomBytes(32).toString(\"hex\")
ts-weak-hash-or-random${TAB}Math.random().toString(16)${TAB}crypto.randomUUID()
ts-unsafe-deserialization${TAB}yaml.load(manifest, { schema: yaml.DEFAULT_FULL_SCHEMA })${TAB}yaml.load(manifest)
ts-unsafe-deserialization${TAB}yaml.load(manifest, { schema: yaml.DEFAULT_SCHEMA })${TAB}yaml.load(manifest)
ts-unsafe-deserialization${TAB}serializer.unserialize(payload)${TAB}JSON.parse(payload)
ts-unsafe-deserialization${TAB}eval(userSuppliedExpression)${TAB}JSON.parse(userSuppliedExpression)
ts-unsafe-deserialization${TAB}new Function(userSuppliedExpression)()${TAB}JSON.parse(userSuppliedExpression)
ts-unsafe-deserialization${TAB}yaml.load(manifest, { schema: DEFAULT_FULL_SCHEMA })${TAB}yaml.load(manifest)
ts-unsafe-deserialization${TAB}  schema: yaml.DEFAULT_FULL_SCHEMA,${TAB}  json: false,
ts-unsafe-deserialization${TAB}new Function(\"a\", \"b\", userSuppliedExpression)${TAB}JSON.parse(userSuppliedExpression)
py-ssrf-url-from-scanned-data${TAB}requests.get(finding[\"evidence_url\"], timeout=TIMEOUT).json()${TAB}requests.get(STATUS_URL, timeout=TIMEOUT).json()
py-ssrf-url-from-scanned-data${TAB}f\"https://{host}/api/v1/findings/{finding_id}\"${TAB}\"https://cloud.tenable.com/api/v1/findings\"
py-ssrf-url-from-scanned-data${TAB}urllib.request.urlopen(finding[\"evidence_url\"]).read()${TAB}urllib.request.urlopen(STATUS_URL).read()
py-ssrf-url-from-scanned-data${TAB}httpx.get(finding[\"callback\"], timeout=TIMEOUT)${TAB}httpx.get(STATUS_URL, timeout=TIMEOUT)
py-failopen-on-exception${TAB}        return True${TAB}        raise RuntimeError(\"policy unreadable\")
py-failopen-on-exception${TAB}        return []${TAB}        raise RuntimeError(\"findings unreadable\")
py-failopen-on-exception${TAB}        pass${TAB}        raise
ts-failopen-on-exception${TAB}    return true;${TAB}    return false;
ts-failopen-on-exception${TAB}    return true; // bound catch: same defect, second pattern branch${TAB}    return false;
ts-failopen-on-exception${TAB}    return [];${TAB}    throw new Error(\"scan failed\");
ts-failopen-on-exception${TAB}    return []; // unbound catch: same defect, fourth pattern branch${TAB}    throw new Error(\"scan failed\");
ts-ssrf-url-from-scanned-data${TAB}await fetch(url);${TAB}await fetch(\"https://api.example.com/status\");
ts-ssrf-url-from-scanned-data${TAB}await fetch(\`https://\${finding.host}/details\`);${TAB}await fetch(\"https://api.example.com/details\");
ts-ssrf-url-from-scanned-data${TAB}axios.post(finding.detailsUrl, { body })${TAB}axios.post(\"https://api.example.com/events\", { body })
ts-ssrf-url-from-scanned-data${TAB}axios.request({ url: finding.detailsUrl, method: \"GET\" })${TAB}axios.get(\"https://api.example.com/x\")
ts-ssrf-url-from-scanned-data${TAB}axios.get(finding.detailsUrl)${TAB}axios.get(\"https://api.example.com/x\")
ts-ssrf-url-from-scanned-data${TAB}axios.put(finding.detailsUrl, { body })${TAB}axios.put(\"https://api.example.com/x\", { body })
ts-ssrf-url-from-scanned-data${TAB}axios.delete(finding.detailsUrl)${TAB}axios.delete(\"https://api.example.com/x\")
ts-ssrf-url-from-scanned-data${TAB}got(finding.detailsUrl)${TAB}got(\"https://api.example.com/x\")
ts-ssrf-url-from-scanned-data${TAB}http.request(finding.detailsUrl)${TAB}http.request(\"http://api.example.com/x\")
ts-ssrf-url-from-scanned-data${TAB}https.request(finding.detailsUrl)${TAB}https.request(\"https://api.example.com/x\")
ts-ssrf-url-from-scanned-data${TAB}await fetch(\`\${config.baseUrl}/api/v1/status\`);${TAB}await fetch(\"https://api.example.com/api/v1/status\");
ts-path-write-without-containment${TAB}fs.writeFileSync(finding.path, body)${TAB}fs.writeFileSync(path.join(OUT, \"report.json\"), body)
ts-path-write-without-containment${TAB}fs.writeFileSync(path.join(OUT, finding.name), body)${TAB}fs.writeFileSync(path.join(OUT, \"named.json\"), body)
ts-path-write-without-containment${TAB}fs.writeFileSync(\`\${OUT}/remediate-\${finding.name}.tf\`, body)${TAB}fs.writeFileSync(\`/var/tmp/reports/remediate.tf\`, body)
ts-path-write-without-containment${TAB}fs.appendFileSync(finding.path, line)${TAB}fs.appendFileSync(path.join(OUT, \"audit.log\"), line)
ts-path-write-without-containment${TAB}fs.appendFile(finding.path, line, () => undefined)${TAB}fs.appendFile(path.join(OUT, \"audit.log\"), line, () => undefined)
ts-path-write-without-containment${TAB}fs.writeFile(finding.path, body, () => undefined)${TAB}fs.writeFile(path.join(OUT, \"report.json\"), body, () => undefined)
ts-path-write-without-containment${TAB}fs.createWriteStream(finding.path)${TAB}fs.createWriteStream(path.join(OUT, \"stream.bin\"))
ts-path-write-without-containment${TAB}fs.promises.writeFile(finding.path, body)${TAB}fs.promises.writeFile(path.join(OUT, \"report.json\"), body)
ts-path-write-without-containment${TAB}fs.promises.appendFile(finding.path, line)${TAB}fs.promises.appendFile(path.join(OUT, \"audit.log\"), line)"
  # NEGATIVE CONTROLS: mutate the VALUE, never the credential-shaped key. The rule must STILL fire
  # on every line. A rule that stops firing here is matching something incidental about the file.
  NCS="ts-token-in-localstorage${TAB}localStorage.setItem(\"access_token\", accessToken)${TAB}localStorage.setItem(\"access_token\", tokenFromParam)
py-caseless-string-case-check${TAB}not \"US-EAST-1\".islower()${TAB}not \"MIXED-Case-9\".islower()
py-negative-control-by-replace${TAB}\"prov1der\"${TAB}\"someOtherReplacement\"
ts-tls-verification-disabled${TAB}export const scannerAgent${TAB}export const renamedScannerAgent
ts-wildcard-cors${TAB}app.get(\"/findings\"${TAB}app.get(\"/vulnerabilities\"
ts-binds-all-interfaces${TAB}app.listen(PORT, \"0.0.0.0\");${TAB}app.listen(OTHER_PORT, \"0.0.0.0\");
ts-untrusted-data-in-llm-system-prompt${TAB}model: \"claude-sonnet-5\"${TAB}model: \"claude-opus-5\"
ts-weak-hash-or-random${TAB}.update(body).digest(\"hex\")${TAB}.update(otherBody).digest(\"base64\")
ts-unsafe-deserialization${TAB}yaml.load(manifest, { schema: yaml.DEFAULT_FULL_SCHEMA })${TAB}yaml.load(otherText, { schema: yaml.DEFAULT_FULL_SCHEMA })
py-ssrf-url-from-scanned-data${TAB}finding[\"evidence_url\"], timeout=TIMEOUT).json()${TAB}finding[\"remediation_url\"], timeout=TIMEOUT).json()
py-failopen-on-exception${TAB}log.warning(\"could not load findings; continuing\")${TAB}log.info(\"could not load findings; retrying\")"

  # Every rule must appear in MUTS -- otherwise 3d can add a rule with no mutation coverage and
  # this whole gate stays green while proving nothing about it.
  uncovered=""
  for y in "$RULES"/*.yaml; do
    b=$(basename "$y" .yaml)
    printf '%s\n' "$MUTS" | cut -f1 | grep -qx "$b" || uncovered="$uncovered $b"
  done
  chk "${uncovered:-none}" "none" "gate5: every rule has a mutation row (uncovered:${uncovered:-none})"

  # Apply the literal first-occurrence replacement using the same awk as mutation-check.sh:86-90.
  apply_mut(){ # $1=src $2=dst $3=old $4=new; rc=3 when nothing changed
    OLD="$3" NEW="$4" awk '
      BEGIN{ o=ENVIRON["OLD"]; n=ENVIRON["NEW"]; done=0 }
      { if(!done){ i=index($0,o); if(i>0){ $0=substr($0,1,i-1) n substr($0,i+length(o)); done=1 } } print }
      END{ if(!done) exit 3 }
    ' "$1" > "$2"
  }
  # ---- Gate 5, batched. ONE `semgrep scan` for every baseline, mutant and negative control. -----
  # Why: a `semgrep scan` costs ~4.8s wall but only ~1.25s user -- ~95% is process startup, not
  # analysis. So the fix is FEWER invocations, not faster ones. Previously each row got its own scan
  # (plus a memoized baseline per rule); now every fixture variant is staged into its own sibling
  # directory under one tree and scanned together, with findings attributed back by `result.path`.
  # Measured on this tree: 60 staged directories analysed in a single 4.8s scan.
  #
  # Correctness of the batch was verified, not assumed, before the rewrite landed:
  #   * Scanning all 10 rules against all 10 fixtures at once reproduces the per-rule line sets
  #     EXACTLY (47 findings, same 10 line lists) -- no cross-rule contamination, because a rule
  #     only matches a fixture whose language it claims and whose defect it targets.
  #   * A broken fixture in one directory does NOT poison its siblings: they still report their
  #     full line sets, and the error carries the offending path so it can be attributed.
  #
  # WHY THE GUARDS BELOW CANNOT BE MUTATION-TESTED THE USUAL WAY, measured: disabling any of them on
  # a HEALTHY tree changes nothing -- 123 passed / 0 failed either way -- because each one only fires
  # on a defect that is not present. Mutating the gate and re-running the suite therefore reports
  # "survivor" for a guard that is in fact load-bearing. The honest test is PAIRED: plant the defect,
  # confirm the catch, then disable the guard and confirm the catch DISAPPEARS. Verdicts recorded
  # per guard below. Two mutations DO show up on a healthy tree, and they are the two that break
  # batching mechanics rather than a guard: collapsing path attribution (59 failures) and silencing
  # the no-JSON tooling-failure path (59 failures).
  #
  # Sibling directories, not a filename prefix, because attribution keys on the DIRECTORY name:
  # fixtures keep their real basename (and therefore their extension, which is what makes semgrep
  # claim the file at all).
  stage_baselines(){ # one unmutated copy per rule -> the line set every mutant is compared against
    for y in "$RULES"/*.yaml; do
      rule=$(basename "$y" .yaml)
      fx=$(find "$RULES" -maxdepth 1 -name "$rule.*" ! -name '*.yaml' | head -1)
      if [ -z "$fx" ]; then echo "  [FAIL] gate5: no fixture for rule $rule"; continue; fi
      mkdir -p "$TREE/base__$rule"; cp "$fx" "$TREE/base__$rule/"
      printf 'base__%s\tbase\t%s\t-\tgate5\tbaseline\n' "$rule" "$rule" >> "$MANIFEST"
    done
  }
  stage_muts(){ # $1=table $2=want(one|same) $3=label
    n=0
    printf '%s\n' "$1" | while IFS="$TAB" read -r rule old new; do
      [ -n "$rule" ] || continue
      n=$((n+1))
      y="$RULES/$rule.yaml"
      fx=$(find "$RULES" -maxdepth 1 -name "$rule.*" ! -name '*.yaml' | head -1)
      if [ ! -f "$y" ] || [ -z "$fx" ]; then
        echo "  [FAIL] $3: no rule+fixture pair for $rule"; continue
      fi
      d="$TREE/${3}__${n}"; mkdir -p "$d"
      # NO-OP DETECTION, and it must stay in the STAGING step where the fixture text is still in
      # hand. A row whose `old` string is absent from the fixture mutates nothing, so the scan sees
      # a pristine fixture and "no findings removed" -- which is precisely what a NEGATIVE CONTROL
      # asserts. Measured: with this check disabled, a no-op row planted in NCS passes vacuously
      # (50 pass / 0 fail instead of 49/1). Load-bearing for the NC table; for the `one` rows it is
      # a better diagnostic than the "expected 1 removed, got 0" that would otherwise fire.
      if ! apply_mut "$fx" "$d/$(basename "$fx")" "$old" "$new"; then
        echo "  [FAIL] $3: $rule '$old' -> '$new' (mutation was a NO-OP -- '$old' not in fixture, proves nothing)"
        rm -rf "$d"; continue
      fi
      printf '%s__%s\tmut\t%s\t%s\t%s\t%s\n' "$3" "$n" "$rule" "$2" "$3" "'$old' -> '$new'" >> "$MANIFEST"
    done
  }
  # gate5-self: Gate 5 must itself be provably alive. A rule that matches the FILE rather than the
  # defect (`languages` + a bare `pattern: localStorage.setItem(...)`) survives every key mutation.
  # It is staged into the SAME tree and judged by the SAME code path as every other row -- on
  # purpose. Run as a separate scan it could keep passing while the batched path was broken, i.e.
  # the optimization would silently disable the check that proves the optimization safe.
  stage_self(){
    fx=$(find "$RULES" -maxdepth 1 -name 'ts-token-in-localstorage.*' ! -name '*.yaml' | head -1)
    mkdir -p "$TREE/base__taut" "$TREE/gate5-self__1"
    cp "$fx" "$TREE/base__taut/f.ts"
    if ! apply_mut "$fx" "$TREE/gate5-self__1/f.ts" '"access_token"' '"theme"'; then
      echo "  [FAIL] gate5-self: staging mutation was a NO-OP -- cannot assess"; return
    fi
    printf 'base__taut\tbase\ttaut\t-\tgate5-self\tbaseline\n' >> "$MANIFEST"
    printf 'gate5-self__1\tmut\ttaut\tinvert\tgate5-self\ta file-matching (tautological) rule is caught\n' >> "$MANIFEST"
  }

  BATCH=$(mktemp -d "${TMPDIR:-/tmp}/sgb.XXXXXX")
  TREE="$BATCH/tree"; MANIFEST="$BATCH/manifest.tsv"
  mkdir -p "$TREE"; : > "$MANIFEST"
  # The tautological rule for gate5-self. Kept OUTSIDE $TREE would be tidier, but it is harmless
  # here: verified that semgrep does not scan a .yaml sitting in the scan root (paths.scanned holds
  # no .yaml), so it cannot become a target of its own rules.
  cat > "$BATCH/taut.yaml" <<'YAML'
rules:
  - id: taut
    languages: [js, ts]
    severity: ERROR
    message: matches any storage call at all -- deliberately tautological
    pattern: localStorage.setItem(...)
YAML
  # Staging writes the manifest; the `find | while` subshell problem means it cannot bump pass/fail
  # itself, so its FAIL lines are folded into the same output that the reporter below produces.
  stage_out=$(stage_baselines; stage_self; stage_muts "$MUTS" one gate5; stage_muts "$NCS" same gate5-nc)

  # ONE scan. Two --config flags compose (verified): the rules dir plus the tautological rule.
  semgrep scan --config "$RULES" --config "$BATCH/taut.yaml" \
    --metrics=off --disable-version-check --json "$TREE" > "$BATCH/scan.json" 2>/dev/null

  report_batch(){
    [ -n "$stage_out" ] && printf '%s\n' "$stage_out"
    SCAN="$BATCH/scan.json" MANIFEST="$MANIFEST" python3 -c '
import json,os,sys,collections
try:
    raw=open(os.environ["SCAN"]).read()
    d=json.loads(raw) if raw.strip() else None
except Exception:
    d=None
if d is None:
    # Empty stdout is meaningful, not an error to swallow: on a broken config `semgrep scan --json`
    # prints nothing. Reported as a tooling failure so it can never read as "every mutant passed".
    print("  [FAIL] gate5: batched scan produced no parseable JSON -- tooling failure, not a result")
    sys.exit(0)

def dirof(p): return os.path.basename(os.path.dirname(p))

found=collections.defaultdict(set)
for r in (d.get("results") or []):
    found[(dirof(r["path"]), r["check_id"].split(".")[-1])].add(r["start"]["line"])
scanned=collections.Counter(dirof(p) for p in ((d.get("paths") or {}).get("scanned") or []))
# Errors arrive as ONE pooled list for the whole batch, so they must be attributed by path or a
# single broken fixture would fail all 55 rows. `path` is not always set -- a PartialParsing error
# carries its file in `spans[].path` -- so both are read, and anything attributable to no fixture
# at all is reported separately rather than dropped.
errs=collections.defaultdict(list); unattributed=[]
for e in (d.get("errors") or []):
    paths=set()
    if e.get("path"): paths.add(dirof(e["path"]))
    for sp in (e.get("spans") or []):
        if sp.get("path"): paths.add(dirof(sp["path"]))
    if paths:
        for p in paths: errs[p].append(e.get("message","(no message)"))
    else: unattributed.append(e.get("message","(no message)"))

rows=[l.rstrip("\n").split("\t") for l in open(os.environ["MANIFEST"]) if l.strip()]

base={}
for dirn,kind,rule,want,label,desc in rows:
    if kind!="base": continue
    # A fixture whose extension the rule never claims reports findings:0 scanned:0 errors:0
    # (measured) -- the likeliest slip when adding rules in bulk.
    # HONESTY NOTE: deleting this scanned check does NOT make the suite pass -- the "baseline found
    # NOTHING" check below still fails. Kept for the DIAGNOSTIC (it names the real cause instead of
    # sending you hunting through a working rule), not as a guard.
    if scanned.get(dirn,0)==0:
        print("  [FAIL] %s %s: baseline fixture was NOT scanned -- extension not claimed by `languages` in the rule?" % (label,rule)); continue
    if errs.get(dirn):
        print("  [FAIL] %s %s: baseline scan reported %d error(s) -- fix the rule/fixture first" % (label,rule,len(errs[dirn]))); continue
    lines=found.get((dirn,rule),set())
    # Also diagnostic rather than load-bearing, and measured the same paired way: delete a baseline
    # fixture outright and the gate reports 8 failures with this check either enabled or disabled --
    # the `scanned` check above gets there first. The pair is kept because between them they name
    # the cause, and which one fires tells you whether the file is missing or merely unclaimed.
    if not lines:
        print("  [FAIL] %s %s: baseline found NOTHING -- cannot assess" % (label,rule)); continue
    base[rule]=lines

for m in unattributed:
    print("  [FAIL] gate5: batched scan reported an error not attributable to any fixture: %s" % m[:200])

def verdict(dirn,rule,want):
    """None when the mutation behaved as required, else the reason it did not."""
    if rule not in base: return "no usable baseline"
    # Diagnostic, not a guard: measured, the line-set check below catches an unscanned mutant
    # anyway ("expected exactly 1 finding removed, got 6"). This just names the real cause.
    if scanned.get(dirn,0)==0: return "fixture was NOT scanned -- broken target, not a removed defect"
    # LOAD-BEARING, and measured on the shipped gate by the paired test: plant an unparseable fixture
    # in one mutant directory and Gate 5 reports 1 failure with this check enabled and 0 with it
    # disabled. The broken fixture reports 0 findings, which without this reads as a legitimately
    # removed defect. Deleting this line does not fail any test on a healthy tree -- that is exactly
    # why the paired test exists, and why this comment is here instead of a naive mutation row.
    if errs.get(dirn): return "semgrep reported %d error(s) -- tooling failure, not a removed defect" % len(errs[dirn])
    mut=found.get((dirn,rule),set()); b=base[rule]
    removed=sorted(b-mut); added=sorted(mut-b)
    # The exit code is not a signal here (a fixture holds MANY findings, so neutralizing one leaves
    # the rest and `--error` still exits 1), which is why the assertion is on the LINE SET.
    if added: return "mutation ADDED finding(s) at line(s) %s" % added
    if want in ("one","invert") and len(removed)!=1: return "expected exactly 1 finding removed, got %d %s" % (len(removed),removed)
    # LOAD-BEARING, measured: swap a negative-control row for a real defect removal and this is the
    # ONLY check that notices (1 gate5 failure with it, 0 without). Without it the NCS table is
    # decorative -- it would assert nothing about whether the rule keys on the value or the defect.
    if want=="same" and removed: return "value-only mutation removed finding(s) at %s -- rule keys on the value, not the defect" % removed
    return None

for dirn,kind,rule,want,label,desc in rows:
    if kind!="mut": continue
    tag="%s: %s %s" % (label,rule,desc)
    v=verdict(dirn,rule,want)
    if want=="invert":
        # INVERTED ON PURPOSE. This row is a rule that SHOULD be judged bad, so a clean verdict is
        # the failure: it means Gate 5 accepted a tautological rule and the whole loop is
        # decorative. Do not "fix" this to match the others.
        # LOAD-BEARING, measured by the paired test: rewrite the taut.yaml pattern to key on the KEY
        # rather than the call (making its subject genuinely non-tautological) and this reports 1
        # failure with the inversion in place, 0 with it removed.
        # NOTE for editors: this whole reporter is inside a single-quoted `python3 -c` block, so an
        # apostrophe anywhere in these comments terminates the shell string and breaks the script.
        if v is None: print("  [FAIL] %s (gate accepted a tautological rule -- gate5 is decorative)" % tag)
        else: print("  [PASS] %s (%s)" % (tag,v))
        continue
    if v is None: print("  [PASS] %s" % tag)
    else: print("  [FAIL] %s (%s)" % (tag,v))

# ---- Gate 5b: coverage at FINDING granularity, not rule granularity. ------------------------
# WHY THIS EXISTS, and it is a defect this gate failed to catch once. The rule-level check above
# ("every rule appears in MUTS") passes as long as a rule has AT LEAST ONE row. So when
# `ts-binds-all-interfaces` gained a whole new `pattern-either` branch for the framework-factory
# idiom (`createMcpExpressApp({host:"0.0.0.0"})`), the new branch shipped with THREE new fixture
# findings and ZERO mutation rows -- and Gate 5 stayed green, because the three pre-existing
# `.listen` rows for that rule still satisfied the old check. NOTE for editors: this block is inside
# a single-quoted `python3 -c` string, so an apostrophe anywhere here breaks the script (shellcheck
# SC1011 catches it). The ablation that proved the new branch worked was
# run by hand in a shell and never committed, so nothing in this suite reproduced it.
# Measured at the time this was added: 11 fixture findings across 6 rules had no row that could
# neutralize them -- 4 of them in the rule that had just been edited.
# The assertion: every baseline finding must be removed by SOME `want=one` row. A finding no row
# can neutralize is a matcher branch with no committed test, which is how a green suite hides new
# untested code. This reuses the results of the batch itself, so it cannot drift from Gate 5.
neutralized=collections.defaultdict(set)
for dirn,kind,rule,want,label,desc in rows:
    if kind!="mut" or want!="one" or rule not in base: continue
    if scanned.get(dirn,0)==0 or errs.get(dirn): continue
    neutralized[rule] |= (base[rule]-found.get((dirn,rule),set()))
gaps=[]
for rule,lines in sorted(base.items()):
    if rule=="taut": continue   # gate5-self scaffolding, judged by inversion above
    un=sorted(lines-neutralized.get(rule,set()))
    if un: gaps.append("%s:%s" % (rule,",".join(str(x) for x in un)))
if gaps:
    print("  [FAIL] gate5b: fixture findings no mutation row can neutralize (untested matcher branches): %s" % "; ".join(gaps))
else:
    print("  [PASS] gate5b: every fixture finding is neutralized by some mutation row")
'; }
  mut_out=$(report_batch)
  printf '%s\n' "$mut_out"
  mp=$(printf '%s\n' "$mut_out" | grep -c '\[PASS\]'); mf=$(printf '%s\n' "$mut_out" | grep -c '\[FAIL\]')
  pass=$((pass+mp)); fail=$((fail+mf))

  # ---- gate5b-self: PAIRED PROOF that gate5b is a real guard. --------------------------------
  # gate5b cannot be mutation-tested the usual way (like every guard in this gate, disabling it on a
  # healthy tree changes nothing -- it only fires on a defect that is not present). So the honest
  # test is paired: reproduce the ACTUAL historical defect and require gate5b to catch it.
  #
  # The defect being reproduced: `ts-binds-all-interfaces` gained a `pattern-either` branch for the
  # framework-factory idiom, adding 3 fixture findings with 0 mutation rows. The rule-level check
  # above stayed green because the rule already had `.listen` rows. Here the 3 factory rows are
  # dropped from the manifest and gate5b must FAIL naming those exact lines.
  #
  # Reuses the SAME scan.json and the SAME reporter -- no extra `semgrep scan` (~5s each, and ~95%
  # of that is process startup), so this proof is nearly free. Filtering the MANIFEST rather than
  # re-staging is what makes that possible.
  grep -v 'createMcpExpressApp' "$MANIFEST" > "$BATCH/manifest.ablated.tsv"
  if [ "$(wc -l < "$MANIFEST")" -eq "$(wc -l < "$BATCH/manifest.ablated.tsv")" ]; then
    echo "  [FAIL] gate5b-self: ablation was a NO-OP -- no factory rows in the manifest, proves nothing"
    fail=$((fail+1))
  else
    ab_out=$(MANIFEST="$BATCH/manifest.ablated.tsv" report_batch 2>&1)
    # Require the exact diagnosis, not merely "something failed": a generic failure could come from
    # any other row and would let a broken gate5b pass this proof.
    if printf '%s\n' "$ab_out" | grep -q '\[FAIL\] gate5b: .*ts-binds-all-interfaces:43,48,55'; then
      echo "  [PASS] gate5b-self: dropping the factory mutation rows makes gate5b fail on lines 43,48,55"
      pass=$((pass+1))
    else
      echo "  [FAIL] gate5b-self: gate5b did NOT catch an untested matcher branch -- it is decorative"
      printf '%s\n' "$ab_out" | grep 'gate5b' | sed 's/^/      /'
      fail=$((fail+1))
    fi
  fi
  rm -rf "$BATCH"

  # ---- Gate 6: the `.semgrepignore` silent zero. --------------------------------------------
  # semgrep's BUNDLED ignore list excludes `tests/`. It says so only on stderr: the JSON
  # `paths.skipped` array stays EMPTY, `errors` stays empty, and rc stays 0 -- so a test-scoped
  # rule reports a clean zero against a repo full of defects. Every measurement below is against
  # a real `git init` repo, because that is the only case that matters (the skill reviews real
  # repos) AND the only case where the workaround differs: in a NON-git directory naming the test
  # DIRECTORY as an extra target is enough, but in a git repo the git-tracked-files filter drops
  # it again. Measured non-fixes, all kept as assertions below so a future semgrep release that
  # changes any of them fails here loudly instead of silently widening coverage:
  #   --no-git-ignore / --project-root / --novcs / naming the tests DIRECTORY / --include tests
  # The two that DO work: naming test FILES explicitly, or an empty .semgrepignore in the
  # target's own root (only appropriate on a repo you own -- hence both are documented).
  W=$(mktemp -d "${TMPDIR:-/tmp}/sgi.XXXXXX")
  mkdir -p "$W/repo/tests"
  ( cd "$W/repo" \
    && git init -q . \
    && git config user.email t@example.invalid \
    && git config user.name t \
    && printf 'def s():\n    MARKER_CALL(1)\n' > src.py \
    && printf 'def t():\n    MARKER_CALL(2)\n' > tests/test_a.py \
    && git add -A && git commit -qm init ) >/dev/null 2>&1
  cat > "$W/probe.yaml" <<'YAML'
rules:
  - id: probe-marker
    pattern: MARKER_CALL(...)
    message: planted marker
    languages: [python]
    severity: ERROR
YAML
  # Assert the fixture itself is sound before drawing conclusions from a zero -- an unscanned or
  # erroring target also reports "no findings", which is the exact confusion this gate is about.
  ig_base=$(scan_lines "$W/probe.yaml" "$W/repo")
  chk "$(printf '%s' "$ig_base" | cut -d'|' -f3)" "0" "gate6-pre: baseline scan is error-free"
  chk "$(printf '%s' "$ig_base" | cut -d'|' -f2)" "1" "gate6-pre: baseline scanned src.py only (tests/ silently dropped)"
  # scan_lines cannot express multi-target or extra-flag invocations, so count findings directly.
  # `grep -c` on the JSON would count the rule id in metadata too; parse instead.
  ig_hits(){ # $@ = extra args + targets -> number of findings
    semgrep scan --config "$W/probe.yaml" --metrics=off --disable-version-check --json "$@" 2>/dev/null \
    | python3 -c 'import json,sys
raw=sys.stdin.read()
try: print(len((json.loads(raw).get("results") or [])))
except Exception: print(-1)'
  }
  chk "$(ig_hits "$W/repo")" "1" "gate6: tests/ defect is MISSED by default (the silent zero)"
  chk "$(ig_hits --no-git-ignore "$W/repo")" "1" "gate6: --no-git-ignore does NOT override it"
  chk "$(ig_hits --project-root "$W/repo" "$W/repo")" "1" "gate6: --project-root does NOT override it"
  chk "$(ig_hits "$W/repo" "$W/repo/tests")" "1" "gate6: naming the tests DIRECTORY does NOT override it (git repo)"
  chk "$(ig_hits "$W/repo" "$W/repo/tests/test_a.py")" "2" "gate6: naming test FILES explicitly DOES find it"
  : > "$W/repo/.semgrepignore"
  chk "$(ig_hits "$W/repo")" "2" "gate6: an empty .semgrepignore in the TARGET root finds it"
  # The other half of the gate, same argument as gate4: remove the override and the defect must go
  # back to being missed. Without this the two passing checks above could both be passing for some
  # unrelated reason and the gate would be decorative.
  rm -f "$W/repo/.semgrepignore"
  chk "$(ig_hits "$W/repo")" "1" "gate6: removing the override restores the silent zero (gate is real)"
  rm -rf "$W"
fi

echo ""
echo "helper-script tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
