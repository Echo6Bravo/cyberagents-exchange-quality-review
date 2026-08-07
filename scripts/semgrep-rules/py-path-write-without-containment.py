"""Planted-defect fixture for py-path-write-without-containment (dimension 2, CWE-22).

Modelled on a real arbitrary-file-write that SHIPPED: a finding's account_id and region were
interpolated into an output filename. Both were validated by an identifier allowlist that permits
"/" -- and must, because S3 keys and Azure resource IDs contain them. An account_id of
"1/../../../../tmp/x" wrote both artifacts outside the --out directory.

The must-NOT-match cases below are not decoration: three of them were FALSE POSITIVES against the
rule shape originally recorded for this rule, and one is a false positive against the version
shipped here (see the KNOWN FALSE POSITIVE note in the .yaml). Unannotated lines that fire will
fail `semgrep test`, so they are enforced true-negative coverage rather than a promise.

No credential-shaped literals anywhere: gitleaks scans full history in CI, so a fixture that trips
it is a permanent build failure that no later commit can undo.
"""

import json
from pathlib import Path

# Named constants, not inline literals, so the Gate 5 mutation table can target the *write* on each
# vulnerable line by a string that occurs exactly ONCE in this file. A mutation `old` string that
# appears twice silently mutates the wrong line, and the resulting failure reads as a rule problem
# rather than a table problem -- measured the hard way while building that gate.
VULN_TEXT = "resource {}\n"
VULN_BYTES = b"PK\x03\x04"


def load_findings(src):
    """The helper that defeats taint mode -- see the .yaml. Real code always has one."""
    return json.loads(Path(src).read_text())


def cmd_generate(src, out_dir):
    """VULNERABLE: filename interpolates scanned data, no containment guard."""
    out_dir = Path(out_dir)
    for f in load_findings(src):
        name = f"remediate-{f['account_id']}-{f['region']}.tf"
        target = out_dir / name
        target.parent.mkdir(parents=True, exist_ok=True)
        # ruleid: py-path-write-without-containment
        target.write_text(VULN_TEXT)


def cmd_generate_bytes(src, out_dir):
    """VULNERABLE: same shape, write_bytes shipping the payload instead."""
    out_dir = Path(out_dir)
    for f in load_findings(src):
        target = out_dir / f"artifact-{f['account_id']}.zip"
        # ruleid: py-path-write-without-containment
        target.write_bytes(VULN_BYTES)


def safe_negative_form(src, out_dir):
    """OK: the guard spelling this rule was originally written against."""
    out_dir = Path(out_dir).resolve()
    for f in load_findings(src):
        target = (out_dir / f"remediate-{f['account_id']}.tf").resolve()
        if not target.resolve().is_relative_to(out_dir):
            raise ValueError("path escapes out_dir")
        target.write_text("resource {}\n")


def safe_positive_form(out_dir, name):
    """OK: guard written the other way round. A FALSE POSITIVE before this was handled."""
    out_dir = Path(out_dir).resolve()
    target = (out_dir / name).resolve()
    if target.resolve().is_relative_to(out_dir):
        target.write_text("resource {}\n")


def safe_assert_form(out_dir, name):
    """OK: assert-form guard. A FALSE POSITIVE before this was handled.

    Note for reviewers: `assert` is the weakest of these spellings -- `python -O` strips it, so in
    an optimized build this containment check does not run at all. The rule accepts it because it
    is lexically a guard; dimension 11's prose is where that gets challenged.
    """
    out_dir = Path(out_dir).resolve()
    target = (out_dir / name).resolve()
    assert target.resolve().is_relative_to(out_dir)
    target.write_text("resource {}\n")


def safe_relative_to_raises(out_dir, name):
    """OK: relative_to() raises ValueError on escape. A FALSE POSITIVE before this was handled."""
    out_dir = Path(out_dir).resolve()
    target = (out_dir / name).resolve()
    target.relative_to(out_dir)
    target.write_text("resource {}\n")


def safe_literal_filename(out_dir):
    """OK: hardcoded filename, so no input reaches the path. A FALSE POSITIVE before the
    literal-path exclusions were added."""
    (Path(out_dir) / "manifest.json").write_text("{}")
