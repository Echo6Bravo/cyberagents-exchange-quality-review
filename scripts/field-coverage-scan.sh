#!/usr/bin/env bash
# field-coverage-scan.sh -- HEURISTIC diff of "fields the model declares" against "fields any
# hostile-value test actually feeds a payload" (quality-review dimension 2, payload-coverage probe).
#
# WHY THIS EXISTS, and why it is not just another injection grep. A real arbitrary-file-write
# shipped in a repo whose hostile-value suite was *thorough*: 24 injection payloads, 4 malicious
# fixtures, every one of them exercised. They all landed on ONE field -- the value that reaches
# shell and HCL, i.e. the sinks the review checklist named. The field that reached a filesystem
# path held the literal "1". The suite was exhaustive along the axis the checklist pointed at and
# blank along the one it did not. So the defect was not a missing payload; it was a payload set
# applied to a single field. That generalizes past path traversal to every future variant of
# "we tested the field we were thinking about", which is why this probe reports a DIFF of two
# field sets rather than looking for any particular vulnerability.
#
# This is a SMELL DETECTOR, not a test. Every uncovered field is a QUESTION -- "does anything
# hostile ever reach this one?" -- to answer by reading the code. Many fields legitimately need no
# payload (an int, an enum, a bool, a value that never leaves the process). Zero uncovered fields
# is NOT proof: it says every declared field is named somewhere in a hostile test, not that the
# payload was appropriate for that field's sink. The whole lesson of the shipped vulnerability is
# that the *right* validator for a shell sink is the *wrong* one for a path sink.
#
# Python only, by design. The two signals it needs -- annotated field declarations and a
# field-identifying kwarg in a hostile test -- have no equivalent shape this can match reliably in
# JS/TS, and a probe that quietly covers less than it claims is the exact failure this kit exists
# to catch. Other languages are a labeled coverage gap, not a silent one.
#
# KNOWN FALSE POSITIVES (measured; triage by reading. Do NOT "fix" these without updating this
# list and the matching tests in test_scripts.sh -- they are locked together):
#   * a field whose payload is passed positionally, or whose hostile test names it only in the test
#     function name. There is no kwarg to match, so it reads as uncovered.
#   * a non-string field (int/bool/enum/datetime) that no payload could meaningfully target.
#   * a field on an internal/report model that never touches untrusted input at all.
#
# KNOWN BLIND SPOTS (this is line-based and will MISS these):
#   * a field fed a payload indirectly -- built into a dict/fixture factory, or through **kwargs.
#     It will read as UNCOVERED (a false positive), never as covered, which is the safe direction.
#   * a field that IS in a hostile test but with a payload wrong for its sink. Covered here,
#     dangerous in reality -- this is precisely the shipped bug, so the probe cannot close it. That
#     judgement is dimension 2's prose question and stays a human's job.
#   * inherited fields declared on a base class in another file.
#   * NON-STRING fields. SET A is restricted to `str` annotations (see below for why), so an int or
#     enum field that reaches a sink after coercion is invisible here.
#
# Exit:   0 = every declared field is named in a hostile test; 1 = uncovered fields (review them);
#         2 = usage error, or nothing to compare (no models or no hostile tests found).
set -u
PROG=$(basename "$0")

case "${1-}" in -h|--help) printf 'usage: %s [path ...]\n' "$PROG"; exit 0 ;; esac

TARGETS=${*:-.}
for t in $TARGETS; do
  [ -e "$t" ] || { echo "$PROG: no such path: $t" >&2; exit 2; }
done

# A hostile test is one naming a recognizable payload-set constant or an injection shape. Kept
# deliberately broad: a missed hostile test understates coverage (fields look uncovered -> more
# questions), which is the safe direction for a probe whose output is questions.
HOSTILE_RE='UNSAFE|MALICIOUS|HOSTILE|INJECT|TRAVERSAL|PAYLOAD|EVIL|\.\./'

# SET A -- fields the code declares, restricted to STRING-typed annotated attributes. The type
# restriction is the difference between a usable probe and noise: measured against a 47-file repo,
# every annotated field gave 154 declarations and 149 "uncovered", which is not a review artifact
# anybody reads. Narrowing to `str` gave 46 -- and it drops precisely the false-positive class this
# header predicts (ints, bools, enums, datetimes that no payload could target), so it raises
# precision without hiding anything a payload could reach. A non-string field that reaches a sink
# via coercion is a blind spot, listed as such below.
declared=$(grep -rhE '^[[:space:]]+[a-z][a-z0-9_]*[[:space:]]*:[[:space:]]*(str|"str"|Optional\[str\]|str[[:space:]]*\|[[:space:]]*None)' \
             --include='*.py' $TARGETS 2>/dev/null \
           | grep -vE '^[[:space:]]*(def|return|if|elif|else|for|while|with|assert|raise|#)' \
           | sed -E 's/^[[:space:]]*//; s/[[:space:]]*:.*$//' \
           | grep -vE '^_' | sort -u)

# SET B -- fields any hostile test points a payload at, via a field-identifying kwarg. Two forms:
# `field_name="x"` / `field="x"` (validator style) and `x=<PAYLOAD>` (constructor style).
hostile_files=$(grep -rlE "$HOSTILE_RE" --include='*.py' $TARGETS 2>/dev/null || true)
if [ -n "$hostile_files" ]; then
  # `field_name=`/`field=` only. A bare `name="..."` was tried and rejected: it matched an unrelated
  # `name = "x"` assignment and reported a field called `x` as covered -- a probe inventing coverage
  # that does not exist is worse than one that misses some, because it turns a gap into a pass.
  covered=$(printf '%s\n' "$hostile_files" | tr '\n' '\0' \
            | xargs -0 grep -hoE '(field_name|field)[[:space:]]*=[[:space:]]*"[a-z][a-z0-9_]*"' 2>/dev/null \
            | sed -E 's/.*"([a-z][a-z0-9_]*)".*/\1/' | sort -u)
  covered="$covered
$(printf '%s\n' "$hostile_files" | tr '\n' '\0' \
   | xargs -0 grep -hoE '\b[a-z][a-z0-9_]*[[:space:]]*=[[:space:]]*[A-Z_]*(UNSAFE|MALICIOUS|HOSTILE|PAYLOAD|EVIL)[A-Z_]*' 2>/dev/null \
   | sed -E 's/^([a-z][a-z0-9_]*).*/\1/' | sort -u)"
  covered=$(printf '%s\n' "$covered" | grep -v '^$' | sort -u)
else
  covered=""
fi

# Refuse to report a clean result when there was nothing to compare. An empty SET A or SET B makes
# the diff meaningless in opposite ways -- no models means nothing to check, no hostile tests means
# EVERY field is uncovered -- and both would otherwise print as a confident zero.
if [ -z "$declared" ]; then
  cat >&2 <<EOF
$PROG: found no annotated field declarations under: $TARGETS
This is NOT a pass. Either there are no models here, or they use a shape this probe cannot see
(positional constructors, dicts, TypedDict, attrs without annotations). Answer dimension 2's
payload-coverage question by hand instead.
EOF
  exit 2
fi
if [ -z "$covered" ]; then
  cat >&2 <<EOF
$PROG: found $(printf '%s\n' "$declared" | wc -l | tr -d ' ') declared field(s) but NO hostile-value tests at all.
That is the finding: every field is uncovered, which is a bigger gap than any diff below would be.
EOF
  exit 1
fi

uncovered=$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$covered"))

n_dec=$(printf '%s\n' "$declared" | wc -l | tr -d ' ')
n_cov=$(printf '%s\n' "$covered" | wc -l | tr -d ' ')

if [ -n "$uncovered" ]; then
  printf '%s\n' "$uncovered" | while IFS= read -r f; do
    [ -n "$f" ] && printf '%s  [no-hostile-payload]\n' "$f"
  done
  n_unc=$(printf '%s\n' "$uncovered" | grep -c . )
  cat <<EOF

$PROG: $n_unc of $n_dec declared field(s) are never named in a hostile-value test
($n_cov field(s) are). Each line above is a QUESTION, not a confirmed bug:

  Does anything untrusted reach this field, and if so, what SINK does it reach?
  A field reaching a filesystem path needs path payloads ("../", a leading "/", ".." as a whole
  segment, a NUL); one reaching shell or SQL needs different ones. An identifier allowlist that
  is correct for a shell sink routinely permits "/" -- because real cloud identifiers require it
  -- and is therefore WRONG for a path sink. Same field, same validator, two verdicts.

  Many of these are fine: ints, enums, bools, and values that never leave the process need no
  payload. Say which, and why, rather than treating the count as a score.
EOF
  exit 1
fi

cat <<EOF
$PROG: all $n_dec declared field(s) are named in at least one hostile-value test.
NOTE: heuristic, not proof -- this checks that each field is NAMED in a hostile test, never that
the payload suited that field's sink. A field tested only with shell-injection payloads while it
reaches a filesystem path reads as covered here and is still vulnerable. That was the real
shipped defect this probe was written for; it cannot detect it. Dimension 2's prose question
stays the primary proof.
EOF
exit 0
