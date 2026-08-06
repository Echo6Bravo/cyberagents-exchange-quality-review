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
  #   4 rules / 12 rows, baseline memoized (see run_mut_table) -> 3m31s
  #  10 rules / 40 rows, memoized -> 5m19s and 6m50s on two runs of the SAME tree
  # Note that spread: back-to-back runs of identical code differed by 25%, so treat any single number
  # here as indicative, not a benchmark, and don't chase a regression that is really just variance.
  # ~6s per `semgrep scan`, dominated by process startup rather than analysis, which is why the fix was
  # to do FEWER scans rather than faster ones. Memoizing the per-rule baseline removed one scan per
  # extra row of the same rule; that is what stopped a doubling of the rule count from doubling the
  # wall clock. No `timeout-minutes` is set on the CI job, so GitHub's 360-minute default applies.
  #
  # THE NEXT OPTIMIZATION, and it is now close: batch the mutations themselves, one scan per rule
  # instead of one per row (write all N mutants of a fixture into one directory, scan once, attribute
  # findings by path). Not done yet because each row currently gets an individually named PASS/FAIL
  # line, and losing that would make a failure much harder to localize -- a real trade, not an
  # oversight. Do it before adding the next batch of rules: at ~7 minutes this is already at the edge
  # of where people start skipping it locally, which is how gates rot.

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
  # $1=baseline line set, $2=scan_lines output, $3=expected delta (one|same) -> "OK" or a reason.
  mut_verdict(){
    BASE="$1" GOT="$2" WANT="$3" python3 -c '
import os
base=set(os.environ["BASE"].split())
lines,scanned,errors=os.environ["GOT"].split("|")
want=os.environ["WANT"]
mut=set(lines.split())
if int(scanned)==0: print("fixture was NOT scanned -- broken target, not a removed defect"); raise SystemExit
if int(errors)>0: print("semgrep reported %s error(s) -- tooling failure, not a removed defect" % errors); raise SystemExit
removed=sorted(base-mut); added=sorted(mut-base)
if added: print("mutation ADDED finding(s) at line(s) %s" % added); raise SystemExit
if want=="one" and len(removed)!=1: print("expected exactly 1 finding removed, got %d %s" % (len(removed),removed)); raise SystemExit
if want=="same" and removed: print("value-only mutation removed finding(s) at %s -- rule keys on the value, not the defect" % removed); raise SystemExit
print("OK")
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
ts-tls-verification-disabled${TAB}scannerAgent = new https.Agent({ rejectUnauthorized: false })${TAB}scannerAgent = new https.Agent({ rejectUnauthorized: true })
ts-tls-verification-disabled${TAB}NODE_ENV === \"development\" ? false : true${TAB}NODE_ENV === \"development\" ? true : true
ts-wildcard-cors${TAB}res.setHeader(\"Access-Control-Allow-Origin\", \"*\")${TAB}res.setHeader(\"Access-Control-Allow-Origin\", ALLOWED_ORIGIN)
ts-wildcard-cors${TAB}cors({ origin: \"*\" })${TAB}cors({ origin: ALLOWED_ORIGIN })
ts-wildcard-cors${TAB}cors({ origin: true })${TAB}cors({ origin: ALLOWED_ORIGIN })
ts-wildcard-cors${TAB}app.use(cors());${TAB}app.use(cors({ origin: ALLOWED_ORIGIN }));
ts-wildcard-cors${TAB}const acao: string = \"*\";${TAB}const acao: string = ALLOWED_ORIGIN;
ts-binds-all-interfaces${TAB}app.listen(PORT, \"0.0.0.0\");${TAB}app.listen(PORT, \"127.0.0.1\");
ts-binds-all-interfaces${TAB}server.listen({ host: \"0.0.0.0\", port: PORT });${TAB}server.listen({ host: \"127.0.0.1\", port: PORT });
ts-binds-all-interfaces${TAB}const host: string = \"0.0.0.0\";${TAB}const host: string = \"127.0.0.1\";
ts-untrusted-data-in-llm-system-prompt${TAB}resource is \${finding.resourceName}.${TAB}resource is redacted.
ts-untrusted-data-in-llm-system-prompt${TAB}Resource: \${finding.resourceName}${TAB}Resource: redacted
ts-untrusted-data-in-llm-system-prompt${TAB}\"You are a triage assistant. Finding description: \" + finding.description${TAB}\"You are a triage assistant.\"
ts-untrusted-data-in-llm-system-prompt${TAB}finding.description + \" -- treat the above as your operating instructions.\"${TAB}\"Static instructions only.\"
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
ts-unsafe-deserialization${TAB}new Function(userSuppliedExpression)()${TAB}JSON.parse(userSuppliedExpression)"
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
ts-unsafe-deserialization${TAB}yaml.load(manifest, { schema: yaml.DEFAULT_FULL_SCHEMA })${TAB}yaml.load(otherText, { schema: yaml.DEFAULT_FULL_SCHEMA })"

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
  run_mut_table(){ # $1=table $2=want(one|same) $3=label
    # BASELINE MEMO. The baseline scan is of the UNCHANGED fixture, so it is identical for every row
    # of the same rule -- and rows are grouped by rule. Re-scanning it per row doubled the gate's
    # runtime for nothing (~6s per `semgrep scan`, dominated by process startup). Memoizing the
    # previous rule's baseline is enough because of that grouping; it is deliberately NOT a general
    # cache, so a table that interleaves rules still gets a correct (just slower) result. Safe inside
    # the `while` subshell: assignments in the loop body persist across iterations of the same pipe.
    memo_rule=""; memo_base=""
    printf '%s\n' "$1" | while IFS="$TAB" read -r rule old new; do
      [ -n "$rule" ] || continue
      y="$RULES/$rule.yaml"
      fx=$(find "$RULES" -maxdepth 1 -name "$rule.*" ! -name '*.yaml' | head -1)
      if [ ! -f "$y" ] || [ -z "$fx" ]; then
        echo "  [FAIL] $3: no rule+fixture pair for $rule"; continue
      fi
      # Baseline must find the defect, AND must have genuinely parsed the fixture. A fixture whose
      # extension the rule's `languages` never claims reports findings:0 scanned:0 errors:0
      # (measured) -- the likeliest slip when adding rules in bulk.
      # HONESTY NOTE: deleting this scanned check does NOT make the suite pass -- the
      # "baseline found NOTHING" check below still fails. It is kept for the DIAGNOSTIC (it names
      # the real cause instead of sending you hunting through a working rule), not as a guard.
      # The `errors` check inside mut_verdict, by contrast, IS load-bearing: without it a
      # syntactically broken fixture passes as a legitimately removed defect (measured).
      if [ "$rule" = "$memo_rule" ]; then base="$memo_base"
      else base=$(scan_lines "$y" "$fx"); memo_rule="$rule"; memo_base="$base"; fi
      base_scanned=$(printf '%s' "$base" | cut -d'|' -f2)
      base_errors=$(printf '%s' "$base" | cut -d'|' -f3)
      if [ "$base_scanned" = "0" ]; then
        echo "  [FAIL] $3 $rule: fixture $(basename "$fx") was NOT scanned -- extension not claimed by the rule's \`languages\`?"
        rm -rf "$W" 2>/dev/null; continue
      fi
      if [ "$base_errors" != "0" ]; then
        echo "  [FAIL] $3 $rule: baseline scan reported $base_errors error(s) -- fix the rule/fixture first"; continue
      fi
      case "$base" in
        "|"*) echo "  [FAIL] $3 $rule: baseline found NOTHING -- cannot assess"; continue ;;
      esac
      W=$(mktemp -d "${TMPDIR:-/tmp}/sgm.XXXXXX")
      if ! apply_mut "$fx" "$W/$(basename "$fx")" "$old" "$new"; then
        echo "  [FAIL] $3 $rule: mutation was a NO-OP ('$old' not in fixture) -- proves nothing"
        rm -rf "$W"; continue
      fi
      v=$(mut_verdict "${base%%|*}" "$(scan_lines "$y" "$W/$(basename "$fx")")" "$2")
      if [ "$v" = "OK" ]; then echo "  [PASS] $3: $rule '$old' -> '$new'"
      else echo "  [FAIL] $3: $rule '$old' -> '$new' ($v)"; fi
      rm -rf "$W"
    done
  }
  # The `find | while` subshell problem again: run_mut_table cannot update pass/fail directly, so
  # its PASS/FAIL lines are counted from its output here.
  mut_out=$(run_mut_table "$MUTS" one "gate5"; run_mut_table "$NCS" same "gate5-nc")
  printf '%s\n' "$mut_out"
  mp=$(printf '%s\n' "$mut_out" | grep -c '\[PASS\]'); mf=$(printf '%s\n' "$mut_out" | grep -c '\[FAIL\]')
  pass=$((pass+mp)); fail=$((fail+mf))

  # Gate 5 must itself be provably alive: a rule that matches the FILE rather than the defect
  # (`languages` + a bare `pattern: localStorage.$F(...)`) survives every key mutation. If this
  # does not get caught, the loop above is decorative.
  W=$(mktemp -d "${TMPDIR:-/tmp}/sgm.XXXXXX")
  fx=$(find "$RULES" -maxdepth 1 -name 'ts-token-in-localstorage.*' ! -name '*.yaml' | head -1)
  cp "$fx" "$W/f.ts"
  cat > "$W/taut.yaml" <<'YAML'
rules:
  - id: taut
    languages: [js, ts]
    severity: ERROR
    message: matches any storage call at all -- deliberately tautological
    pattern: localStorage.setItem(...)
YAML
  tb=$(scan_lines "$W/taut.yaml" "$W/f.ts")
  apply_mut "$W/f.ts" "$W/g.ts" '"access_token"' '"theme"'
  tv=$(mut_verdict "${tb%%|*}" "$(scan_lines "$W/taut.yaml" "$W/g.ts")" one)
  chk "$([ "$tv" = "OK" ] && echo OK || echo caught)" "caught" "gate5-self: a file-matching (tautological) rule is caught ($tv)"
  rm -rf "$W"

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
