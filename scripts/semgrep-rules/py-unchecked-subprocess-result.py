# Planted-defect fixture for py-unchecked-subprocess-result (dim 3, CWE-252).
#
# Two defect shapes: a subprocess.run whose returncode is never inspected before returning success,
# and a poll() loop that returns True with the exit value never branched on (the AI Goat runner.run
# shape). Each must-catch line carries a string that appears EXACTLY ONCE so the Gate 5 mutation table
# can neutralise one finding at a time. The correct sibling of each shape sits alongside it and must
# stay silent.
#
# This prose must never spell the annotation keyword (starts with "rule", ends with "id") followed by
# a colon: semgrep reads it as a real annotation wherever it appears.

import subprocess


def run_via_run_unchecked(cmd):
    # The unused `result` IS the planted defect: the exit status is never read. ruff F841 flags the
    # unused binding for the same reason the rule does, but this fixture must keep the assigned-and-
    # ignored shape verbatim, so silence F841 narrowly rather than dropping the binding (which would
    # change the shape the rule matches). Never widen this to a file-level ignore.
    # ruleid: py-unchecked-subprocess-result
    result = subprocess.run(cmd, capture_output=True, text=True)  # noqa: F841, PLW1510
    print("[+] started")
    return True


def run_ai_goat_poll(os_command, happy_msg):
    process = subprocess.Popen(os_command, stdout=subprocess.PIPE, universal_newlines=True)
    # ruleid: py-unchecked-subprocess-result
    while True:
        output = process.stdout.readline()
        print("    > ", output.strip())
        return_code = process.poll()
        if return_code is not None:
            for output in process.stdout.readlines():
                print("    > ", output.strip())
            break
    print(happy_msg)
    return True


# ---- must-NOT-catch: correct forms. None of these should fire. ----

def run_checked_value(cmd):
    # This is the CORRECT counterpart the rule must SPARE: it reads `.returncode` and fails closed.
    # It deliberately does NOT pass check= (it handles the code itself), so ruff PLW1510 fires; and
    # the explicit if/return is the shape the rule matches on, so SIM103's "return the condition
    # directly" rewrite would erase what this fixture is demonstrating. Both silenced narrowly.
    # ok: py-unchecked-subprocess-result
    outcome = subprocess.run(cmd, capture_output=True, text=True)  # noqa: PLW1510
    if outcome.returncode > 0:  # noqa: SIM103
        return False
    return True


def run_check_true(cmd):
    # check=True raises on non-zero, so the exit code IS handled (as an exception). The binding is
    # unused on purpose -- the point is that check=True alone makes this correct. F841 silenced
    # narrowly for the same reason as above.
    # ok: py-unchecked-subprocess-result
    verified = subprocess.run(cmd, check=True, capture_output=True, text=True)  # noqa: F841
    return True


def run_poll_checked(os_command):
    # ok: py-unchecked-subprocess-result
    proc = subprocess.Popen(os_command, stdout=subprocess.PIPE)
    while True:
        poll_code = proc.poll()
        if poll_code is not None:
            break
    if poll_code != 0:
        return False
    print("finished")
    return True
