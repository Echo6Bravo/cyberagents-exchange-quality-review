"""Planted-defect fixture for py-caseless-string-case-check (dimension 11).

Both real shapes are here because the severity differs by two rubric rows depending on which one
you found: a guard that rejects valid input (High) and a test assertion that passes for the wrong
reason (Medium). The rule cannot distinguish them, so the fixture keeps both visible.

The must-NOT-match cases are enforced coverage, not decoration: an unannotated line that fires
fails `semgrep test`, so the two documented false-positive exclusions cannot silently rot.
"""

# A region identifier: lowercase letters, digits, hyphens. "us-east-1".islower() is True only
# because of the letters. An all-digit account-style value makes it False -- that asymmetry is the
# entire defect, and it is invisible when you only ever test with realistic-looking strings.
REGION = "us-east-1"
ALL_DIGITS = "111111111111"


def guard_region(region):
    """VULNERABLE (High -- a guard): rejects every all-digit or empty value.

    ALL_DIGITS.islower() is False, so this raises on a value that contains no uppercase character
    at all. The caller sees "region must be lowercase" for a string that already is.
    """
    # ruleid: py-caseless-string-case-check
    if not region.islower():
        raise ValueError("region must be lowercase")
    return region


def guard_code_upper(code):
    """VULNERABLE (High -- a guard): the .isupper() mirror of the same defect."""
    # ruleid: py-caseless-string-case-check
    if not code.isupper():
        raise ValueError("code must be uppercase")
    return code


def test_rejects_uppercase_region():
    """VULNERABLE (Medium -- a test): passes without evaluating its claim.

    True for "US-EAST-1", and equally true for "123" and "". The assertion cannot distinguish
    "correctly rejected an uppercase region" from "was handed something uncased", so it will keep
    passing after guard_region is rewritten to do nothing.
    """
    # ruleid: py-caseless-string-case-check
    assert not "US-EAST-1".islower()


def ok_guarded_by_isalpha(word):
    """OK: .isalpha() guarantees at least one character and all of them cased, so .islower() means
    what it looks like here. Excluded, and measured load-bearing -- dropping the exclusion from the
    .yaml makes this line fire."""
    if word.isalpha() and word.islower():
        return word
    raise ValueError("expected a lowercase word")


def ok_correct_form(region):
    """OK: the correct predicate. True for "us-east-1", "111111111111" and "" alike."""
    if region != region.lower():
        raise ValueError("region must be lowercase")
    return region


def ok_correct_form_upper(code):
    """OK: the .upper() equivalent."""
    if code != code.upper():
        raise ValueError("code must be uppercase")
    return code


def ok_formatting_choice(name):
    """OK: not an assertion or a guard -- a display decision, where "has no cased characters" and
    "is already lowercase" both correctly mean "leave it alone". This was a false positive until the
    ternary exclusion went in; see the .yaml for why `pattern-not` could not do it."""
    return name.title() if name.islower() else name
