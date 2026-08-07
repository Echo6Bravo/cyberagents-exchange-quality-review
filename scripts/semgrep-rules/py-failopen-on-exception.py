"""Planted-defect fixture for py-failopen-on-exception (dim 3, CWE-636, OWASP A10:2025).

Modelled on the failure this artifact class produces most often and notices least: the tool cannot
read its input, says so in a log line nobody reads, and hands the caller a permissive value. The
`return []` case is the one to study -- `log.warning()` followed by an empty list is what an author
writes when they believe they have handled the error, and it renders downstream as "we scanned your
environment and found no findings."

The must-NOT-match cases are enforced coverage: `semgrep test` fails on any unannotated line that
fires. Both correct forms below are real alternatives, not strawmen -- one raises, one fails closed
with a logged error.

Every `except Exception:` here carries `# noqa: BLE001`, and the bare-pass case also carries
`# noqa: S110`. Those are not lint appeasement -- the blind except is *half the planted defect*, so
"fixing" it would delete the fixture. Note the measured fact behind them: ruff 0.16.1's DEFAULT rule
set includes S102/S110/S112, a subset of flake8-bandit, so this repo's "ruff's S rules stay off"
policy is true only of the ones it does not select by default. Each noqa is narrow and carries its
reason, per the house rule; do not widen either into a file-level exclude.

No credential-shaped literals anywhere: gitleaks scans full history in CI, so a fixture that trips it
is a permanent build failure that no later commit can undo.
"""

import json
import logging
from pathlib import Path

log = logging.getLogger(__name__)

# Named constants so the Gate 5 mutation table can target each vulnerable line by a string that
# occurs exactly ONCE in this file -- an `old` string appearing twice mutates the wrong line and the
# failure then reads as a rule problem rather than a table problem.
COMPLIANT_KEY = "compliant"
FINDINGS_KEY = "findings"

# OK: the documented excluded class -- probing for an optional dependency. Nothing is being decided
# here, so swallowing ImportError is correct, and module level is where these probes actually live.
#
# Deliberately at module scope, which is BOTH more realistic and load-bearing for Gate 5: as a
# function its handler and body were indented eight spaces, which collided character-for-character
# with the two vulnerable lines below. The mutation table would then have depended on awk's
# first-occurrence ordering rather than on unique strings, and a later reordering of this file would
# silently mutate the wrong line. At module scope the handler sits at four spaces, so both stay
# unique -- do not indent this block into a function, and do not quote the colliding forms in this
# comment, because a comment occurrence is itself a collision (measured: it came first in the file
# and would have been mutated instead of the code).
try:
    import botocore  # noqa: F401  (optional dependency, probed at runtime)

    HAS_BOTOCORE = True
except ImportError:
    pass


def vuln_returns_true(policy_path):
    """VULNERABLE: an unreadable policy file reports COMPLIANT.

    This is the shape that matters most: the permissive value is indistinguishable from a real pass,
    so a broken deployment shows a green dashboard indefinitely.
    """
    # ruleid: py-failopen-on-exception
    try:
        return json.loads(Path(policy_path).read_text())[COMPLIANT_KEY]
    except Exception:  # noqa: BLE001  (the blind except is HALF the planted defect; see module docstring)
        return True


def vuln_returns_empty_after_logging(src):
    """VULNERABLE: logs, then reports NO FINDINGS for a scan that did not happen.

    The log line is why this survives review, and the leading `...` in the rule's handler pattern is
    what catches it -- see the ablation note in the .yaml.
    """
    # ruleid: py-failopen-on-exception
    try:
        return json.loads(Path(src).read_text())[FINDINGS_KEY]
    except Exception:  # noqa: BLE001  (the blind except is HALF the planted defect; see module docstring)
        log.warning("could not load findings; continuing")
        return []


def vuln_bare_pass(src, results):
    """VULNERABLE: silently drops a result. The only one of the three that bandit B110 also sees."""
    # ruleid: py-failopen-on-exception
    try:
        results.append(json.loads(Path(src).read_text()))
    # S110 anchors to the `except` line, not the `try` -- measured; a noqa on `try:` reports RUF100.
    except Exception:  # noqa: BLE001,S110  (try/except/pass IS the planted defect; the 1 of 3 shapes bandit B110 also sees)
        pass


def safe_reraise(policy_path):
    """OK: fails loudly. The caller cannot mistake this for a pass."""
    try:
        return json.loads(Path(policy_path).read_text())[COMPLIANT_KEY]
    except Exception as exc:
        raise RuntimeError("policy unreadable -- refusing to report a result") from exc


def safe_fail_closed(policy_path):
    """OK: fails closed. Note this still conflates "not compliant" with "could not check" -- a third
    state (UNAVAILABLE) is better, and dimension 3's prose is where that gets asked. The rule accepts
    this because failing closed is not a security defect."""
    try:
        return json.loads(Path(policy_path).read_text())[COMPLIANT_KEY]
    except Exception:  # noqa: BLE001  (broad catch is deliberate: any parse failure must fail closed)
        log.error("policy unreadable -- failing closed")
        return False
