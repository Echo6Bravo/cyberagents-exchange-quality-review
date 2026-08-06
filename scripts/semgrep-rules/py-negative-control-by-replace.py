"""Planted-defect fixture for py-negative-control-by-replace (dimension 11).

Modelled on twelve real negative-control tests that built their "invalid" input by calling
`.replace()` on a known-good string with a needle that was not in it. Every one passed. Every one
would have started FAILING the moment the checker it guarded was fixed, because the value it fed in
was valid the whole time.

Note where the annotations sit: the match is reported on the MUTATION line, not on the assertion.
That is worth knowing before triaging a real hit -- the reported line is where the silently-valid
value is built, and the assertion that makes it a defect is a few lines below. (Spelling the
annotation keyword out in this docstring makes semgrep's test parser treat the prose as a
misplaced annotation and print an error, so it stays paraphrased here.)

The must-NOT-match cases are enforced coverage: an unannotated line that fires fails `semgrep test`,
so the presence-guard exclusion and the normalize-then-accept shape cannot silently rot.

No credential-shaped literals: gitleaks scans full history in CI, so a fixture that trips it is a
permanent build failure no later commit can undo.
"""

import re

import pytest

# The known-good artifact these tests mutate. Note what it does NOT contain: the word "provider".
# That absence is the whole defect -- every `.replace("provider", ...)` below is a no-op returning
# this string unchanged.
GOOD_HCL = 'resource "aws_s3_bucket" "b" {}\n'


def validate(text):
    """Stand-in for the real checker. Accepts anything naming the expected resource type."""
    return "aws_s3_bucket" in text


def validate_strict(text):
    """Raising variant, so the pytest.raises case below has something real to call."""
    if "aws_s3_bucket" not in text:
        raise ValueError("unknown block type")
    return text


def test_rejects_unknown_block_type():
    """VULNERABLE: "provider" is not in GOOD_HCL, so `broken` IS GOOD_HCL.

    This asserts that a VALID artifact is rejected. It passes only because `validate` is imperfect;
    fix `validate` and this test breaks, which is the signature of an inverted negative control.
    """
    # ruleid: py-negative-control-by-replace
    broken = GOOD_HCL.replace("provider", "prov1der")
    assert not validate(broken)


def test_rejects_bad_region_via_resub():
    """VULNERABLE: same silent no-op through `re.sub` -- the pattern matches nothing."""
    # ruleid: py-negative-control-by-replace
    damaged = re.sub("us-west-9", "??", GOOD_HCL)
    assert not validate(damaged)


def test_raises_on_unknown_block_type():
    """VULNERABLE: the `pytest.raises` spelling of the same inversion.

    Worse than the `assert not` form in one way: it reads as the most rigorous kind of negative
    test, and the context manager will only report "DID NOT RAISE" after someone fixes the checker
    -- so the failure arrives attached to the fix, not to the bug.
    """
    # ruleid: py-negative-control-by-replace
    unmatched = GOOD_HCL.replace("datasource", "dat4source")
    with pytest.raises(ValueError):
        validate_strict(unmatched)


def test_needle_in_a_local_variable():
    """VULNERABLE, and caught: identical defect with the needle held in a local variable.

    Matched because semgrep does CONSTANT PROPAGATION on the literal assignment -- which was
    measured, not assumed, after this case was first written down as a blind spot and turned out to
    fire. A needle that is a function parameter or a computed expression is genuinely invisible; see
    the unannotated case at the bottom.
    """
    needle = "provider"
    # ruleid: py-negative-control-by-replace
    broken = GOOD_HCL.replace(needle, "prov-1-der")
    assert not validate(broken)


def test_presence_asserted_first():
    """OK: the one-line fix. The presence assertion makes the no-op impossible, so the mutation is
    guaranteed to have happened and the rejection means what it says."""
    assert "aws_s3_bucket" in GOOD_HCL
    mutant = GOOD_HCL.replace("aws_s3_bucket", "aws_s3_bucketz")
    assert not validate(mutant)


def test_presence_asserted_first_resub():
    """OK: the same fix for the `re.sub` form."""
    assert "aws_s3_bucket" in GOOD_HCL
    mutant = re.sub("aws_s3_bucket", "aws_s3_bucketz", GOOD_HCL)
    assert not validate(mutant)


def test_explicit_mutant():
    """OK: constructed directly rather than derived. Nothing can silently no-op."""
    mutant = 'resource "" "b" {}\n'
    assert not validate(mutant)


def test_normalizes_then_accepts():
    """OK: `.replace()` used to NORMALIZE input and then asserting ACCEPTANCE. A no-op here is
    harmless -- it means there was nothing to normalize -- so this is not a negative control at all
    and must not fire."""
    normalized = GOOD_HCL.replace("\r\n", "\n")
    assert validate(normalized)


def test_nonconstant_needle_blind_spot(needle):
    """OK to this rule, but a REAL DEFECT -- the documented blind spot, kept visible on purpose.

    Same bug as the first test, with a needle the engine cannot resolve to a literal (here a
    parameter; a computed expression like "prov" + suffix behaves the same, both measured MISSED).
    Left unannotated so that if a future rule version learns to see through it, `semgrep test`
    FAILS here and forces the blind-spot list in the .yaml to be updated rather than letting it
    drift quietly out of date.
    """
    broken = GOOD_HCL.replace(needle, "prov1der")
    assert not validate(broken)
