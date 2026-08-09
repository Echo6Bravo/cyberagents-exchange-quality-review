"""Planted-defect fixture for py-empty-default-decides-exclusion (dim 1, CWE-1288, OWASP A04:2025).

Modelled on a real defect found while reviewing a cloud attack-path tool: a component->port table
consulted with `.get(key, set())`, whose empty default then made a reachability test unconditionally
false, so any component missing from the table had its findings silently DROPPED. The invariant held
at the commit reviewed -- but nothing asserted it, so the next service added to the alias table would
have lost its findings with no error and no log line.

WHY THERE ARE FIVE VULNERABLE FUNCTIONS AND NOT ONE. The rule's first working version caught only
`vuln_intersection_then_drop` -- the exact spelling in the repo that prompted it -- and missed the
other four, which express the identical defect. Each function below pins one arm of the rule's
`pattern-either`. They are the coverage bound, not repetition: delete one and the rule can regress to
matching a single house style while still reporting itself as dimension-1 coverage. Add a sixth
spelling only together with its arm.

The must-NOT-match cases are enforced coverage: `semgrep test` fails on any unannotated line that
fires, so every `ok_*` function below is a live negative control rather than documentation. Three of
them matter individually:
  * `ok_membership_guard_first` is what the rule's `pattern-not-inside` exists for -- measured, without
    that clause this function fires and the rule's findings go from [1 defect] to [1 defect + 1 FP].
  * `ok_accumulator_union` is the dominant real-world shape of an empty-collection default, verified by
    reading every such site in a 92-file repo: empty is the correct IDENTITY ELEMENT for `|`, and no
    exclusion follows.
  * `ok_fail_closed_explicit_check` is the FAIL-CLOSED counterpart, and it is the reason this is a
    semgrep rule rather than a fourth `empty-relationship-scan.sh` regex. It is textually almost
    identical to the defect; only the explicit absent-key check distinguishes them, and no line-based
    grep can see that difference.

No credential-shaped literals anywhere: gitleaks scans full history in CI, so a fixture that trips it
is a permanent build failure that no later commit can undo.
"""

# Module-level tables, so each vulnerable line's `.get(` call sits at a distinct indentation and text.
# Named distinctly on purpose: the Gate 5 mutation table targets lines by a string that must occur
# exactly ONCE in this file, and an `old` string appearing twice mutates the wrong line -- which then
# reads as a rule defect rather than a table defect.
SERVICE_PORTS = {"nginx": {80, 443}, "sshd": {22}}
ROLE_ACTIONS = {"admin": {"iam:*"}, "reader": {"s3:Get*"}}
TENANT_REGIONS = {"acct-1": {"us-east-1"}}


def vuln_intersection_then_drop(service, observed_ports):
    """VULNERABLE: a service absent from the table is reported as NOT REACHABLE.

    The original shape. `need` is empty for an unknown service, so the intersection is empty, so the
    finding is dropped -- indistinguishable in the output from a service that genuinely does not
    listen on any observed port.
    """
    # ruleid: py-empty-default-decides-exclusion
    need_ports = SERVICE_PORTS.get(service, set())
    if not (observed_ports & need_ports):
        return ("drop", "not reachable")
    return ("keep", "reachable")


def vuln_operands_reversed(service, observed_ports):
    """VULNERABLE: identical defect, operands swapped. Missed by the rule's first version."""
    # ruleid: py-empty-default-decides-exclusion
    reversed_need = SERVICE_PORTS.get(service, set())
    if not (reversed_need & observed_ports):
        return ("drop", "not reachable")
    return ("keep", "reachable")


def vuln_isdisjoint(role, requested_actions):
    """VULNERABLE: `isdisjoint` spelling. An unknown role is disjoint from everything, so this reads
    as "no privileged actions" for a role nobody mapped."""
    # ruleid: py-empty-default-decides-exclusion
    allowed = ROLE_ACTIONS.get(role, set())
    if requested_actions.isdisjoint(allowed):
        return ("drop", "no overlap with privileged actions")
    return ("keep", "privileged")


def vuln_len_zero_in_loop(tenant, candidate_regions):
    """VULNERABLE: `len(...) == 0`, and the exclusion is a `continue` rather than a `return` -- the
    loop shape, which is where this defect does the most damage because it drops rows one at a time
    and reports a plausible-looking total."""
    kept = []
    for regions in candidate_regions:
        # ruleid: py-empty-default-decides-exclusion
        expected = TENANT_REGIONS.get(tenant, set())
        if len(regions & expected) == 0:
            continue
        kept.append(regions)
    return kept


def vuln_issubset(role, granted_actions):
    """VULNERABLE: `issubset` spelling. The empty set is a subset of EVERYTHING, so `not
    empty.issubset(x)` is always False -- an unknown role never trips the check at all."""
    # ruleid: py-empty-default-decides-exclusion
    required = ROLE_ACTIONS.get(role, set())
    if not required.issubset(granted_actions):
        return ("drop", "required actions not granted")
    return ("keep", "granted")


def ok_membership_guard_first(service, observed_ports):
    """OK: the absent key is excluded BEFORE the default can be reached, so the empty default is
    unreachable and the set test only ever runs on real data. This is what the rule's
    `pattern-not-inside` clause is for -- measured: removing that clause makes this fire."""
    if service not in SERVICE_PORTS:
        raise KeyError(f"unmapped service {service!r} -- refusing to judge reachability")
    # The local is named distinctly from the vulnerable functions' `need` on purpose: the Gate 5
    # mutation rows key on the `if` line, and an identical `if` line here would make the row's `old`
    # string ambiguous (awk replaces the FIRST occurrence, so it would still land -- but by luck of
    # file order, which is not a property to depend on).
    mapped_ports = SERVICE_PORTS.get(service, set())
    if not (observed_ports & mapped_ports):
        return ("drop", "not reachable")
    return ("keep", "reachable")


def ok_fail_closed_explicit_check(service, observed_ports):
    """OK: the fail-CLOSED counterpart, and the reason this rule exists instead of a regex. An
    unmapped service is routed to an explicit third state rather than dropped, so "never mapped" can
    never render as "not reachable"."""
    if service not in SERVICE_PORTS:
        return ("review", "unmapped service -- reachability unconfirmed, not a negative result")
    need = SERVICE_PORTS[service]
    if not (observed_ports & need):
        return ("drop", "not reachable")
    return ("keep", "reachable")


def ok_accumulator_union(pairs):
    """OK: the dominant real-world shape -- an accumulator union, where the empty set is the correct
    identity element for `|` and no exclusion decision follows it."""
    seen = {}
    for name, ports in pairs:
        seen[name] = seen.get(name, set()) | ports
    return seen


def ok_no_exclusion_follows(service):
    """OK: an empty default used as a VALUE. Nothing is decided, so there is nothing to fail open."""
    need = SERVICE_PORTS.get(service, set())
    return sorted(need)


def ok_dict_default_for_display(record):
    """OK: a non-set default, outside the rule's scope by design. Documented as a blind spot rather
    than guessed at -- see the .yaml header."""
    meta = record.get("metadata", {})
    return str(meta.get("apiVersion", ""))


# The two cases below exist ONLY to make the `metavariable-pattern` set()/frozenset() constraint
# gate-enforced, and they were added after an ablation caught the gap: deleting that constraint left
# `semgrep test` PASSING, because nothing in this fixture had a non-set default reaching a set
# operation. The constraint is genuinely load-bearing -- measured separately, removing it makes the
# rule fire on both functions below (a dict default and a None default feeding the same exclusion) --
# but a load-bearing element that no fixture case exercises is an UNGUARDED element, which is this
# skill's dimension 11 applied to its own rules. With these two present, dropping the constraint now
# fails the test. Do not delete them as redundant with `ok_dict_default_for_display`: that one is a
# display path with no exclusion, so it does not exercise the constraint either.


def ok_dict_default_reaches_setop(table, observed):
    """OK-by-scope: a `{}` default DOES reach a set-op exclusion here, and the rule deliberately does
    not match it -- at runtime this is a TypeError, not a silent drop, so it fails loudly. Guards the
    `metavariable-pattern` constraint."""
    need = table.get("nginx", {})
    if not (observed & need):
        return ("drop", "not reachable")
    return ("keep", "reachable")


def ok_none_default_reaches_setop(table, observed):
    """OK-by-scope: same for a `None` default. Also a loud TypeError rather than a silent false
    negative, which is why the rule's scope stops at empty *collections*."""
    need = table.get("nginx", None)
    if not (observed & need):
        return ("drop", "not reachable")
    return ("keep", "reachable")
