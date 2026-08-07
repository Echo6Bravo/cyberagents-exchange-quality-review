#!/usr/bin/env python3
"""pinned-vuln-scan.py -- find dependencies that are correctly PINNED and known VULNERABLE
(quality-review dimension 18, supply-chain provenance).

WHY THIS EXISTS. Dimension 18 asks whether dependencies are pinned: an exact version, a digest,
no moving tags. A submission that pins everything passes it. But "pinned" and "safe" are
different properties, and a pin does not merely fail to help -- it is the mechanism that KEEPS
you on the vulnerable version, because the fix can never arrive on its own. So the dimension as
written can hand a clean bill of health to a repo that is pinned precisely TO a known-vulnerable
release. This probe closes that specific gap and nothing wider.

Unlike every other script in scripts/, this is NOT a heuristic. A hit means the pinned version
falls inside a range that the GitHub Advisory Database states is vulnerable, and the advisory is
named so a reviewer can read it. The judgement left to a human is reachability and severity in
context, not whether the fact is real.

REQUIRES NETWORK + `gh` AUTH. That is a deliberate trade: `gh` is already a stated prerequisite
of this skill, whereas pip-audit and osv-scanner would each be a new install, and the GitHub API
is reachable in environments where semgrep's registry and CodeQL's query packs are not. When the
query cannot run, this script exits 2 -- it never reports "no vulnerabilities found" on the
strength of a failed lookup, which is the silent zero the whole toolkit is built to avoid.

Usage:  pinned-vuln-scan.py [path ...]        (defaults to ".")
        pinned-vuln-scan.py --self-test       (offline; no network, no gh)
Exit:   0 = no pinned-and-vulnerable dependency found
        1 = at least one found (read them)
        2 = could not complete the check (no gh, no auth, network failure, usage error)
"""
import json
import os
import re
import subprocess
import sys
import tempfile

PROG = os.path.basename(__file__)

# ---------------------------------------------------------------------------------------------
# Version comparison.
#
# A hand-rolled comparator is a liability, so this one is not trusted on inspection: it is
# differentially tested against `packaging.version` over 144,199 ordered pairs built from every
# version string in the harvested advisory corpus (100.0% agreement), and against the semver
# spec's own normative precedence chain (section 11). `packaging` is NOT importable on 3 of the 4
# interpreters on the development machine, so it cannot be a runtime dependency -- it is used as
# a TEST-TIME ORACLE instead. See test_scripts.sh and the header of test_pinned_vuln_data.json.
#
# Getting this lenient in either direction is not a cosmetic bug: a comparator that places a
# vulnerable version outside its range reports a clean result on vulnerable code.
# ---------------------------------------------------------------------------------------------

# PEP440 normalizes a==alpha, b==beta, c==rc==pre==preview, so those share a rank. semver
# compares identifiers lexically, where alpha<beta<canary<rc also holds -- one table satisfies both.
_PRE_RANK = {'dev': -1, 'a': 0, 'alpha': 0, 'b': 1, 'beta': 1,
             'canary': 2, 'c': 3, 'rc': 3, 'pre': 3, 'preview': 3}
# LONGEST ALTERNATIVE FIRST, and this is load-bearing. With 'b' ahead of 'beta' the regex matches
# 'b', never consumes the '.8' of 'beta.8', and beta.1/beta.8 collapse to the same key. That was
# measured as 3 disagreements against the oracle, not anticipated.
_PRE_RE = re.compile(r'^(alpha|beta|preview|canary|dev|pre|rc|a|b|c)[.\-_]?(.*)$')


def _ident_key(tok):
    """semver 11: numeric identifiers compare numerically and rank BELOW alphanumeric ones."""
    return (0, int(tok), '') if tok.isdigit() else (1, 0, tok)


def parse_version(s):
    """(epoch, release_tuple, phase, pre_key, post_num); phase 0=pre, 1=release, 2=post."""
    s = re.sub(r'^[vV]', '', str(s).strip())
    epoch = 0
    m = re.match(r'^(\d+)!(.*)$', s)
    if m:
        epoch, s = int(m.group(1)), m.group(2)
    s = s.split('+')[0]                       # build metadata is never significant
    m = re.match(r'^([0-9][0-9.]*)(.*)$', s)
    rel, tail = (m.group(1), m.group(2)) if m else (s, '')
    nums = tuple(int(x) for x in rel.rstrip('.').split('.') if x != '')
    t = tail.lower().lstrip('.-_')
    if t == '':
        return (epoch, nums, 1, (), 0)
    m2 = _PRE_RE.match(t)
    if m2:
        idents = tuple(_ident_key(x) for x in m2.group(2).split('.') if x != '')
        return (epoch, nums, 0, ((0, _PRE_RANK[m2.group(1)], ''),) + idents, 0)
    if t.startswith(('post', 'r')):
        m3 = re.search(r'(\d+)', t)
        return (epoch, nums, 2, (), int(m3.group(1)) if m3 else 0)
    # Bare numeric tail ("1.7.1-2"): PEP440 reads it as a POST-release and the oracle agrees;
    # semver would read it as a PRE-release. A real divergence, documented rather than hidden.
    # Occurs twice in the harvested corpus, both PIP, never in npm data.
    m3 = re.search(r'(\d+)', t)
    return (epoch, nums, 2, (), int(m3.group(1)) if m3 else 0)


def vcmp(a, b):
    """-1 / 0 / 1. Release tuples are zero-padded, so 1.24 == 1.24.0."""
    ea, na, pa, ka, sa = parse_version(a)
    eb, nb, pb, kb, sb = parse_version(b)
    n = max(len(na), len(nb))
    na, nb = na + (0,) * (n - len(na)), nb + (0,) * (n - len(nb))
    # Pre-release identifier lists are deliberately NOT padded. semver requires a shorter prefix
    # to rank lower ("1.0.0-alpha" < "1.0.0-alpha.1"), and Python's tuple comparison already does
    # exactly that. A sentinel-padding version of this line was written, then MEASURED INERT:
    # identical results on all 276,396 pairs over the corpus plus synthetic prefix cases. It was
    # deleted rather than shipped, because a line that looks protective and does nothing is worse
    # than its absence -- it is the same call made against the `.with_suffix()` exclusion in
    # py-path-write-without-containment.yaml. Release tuples above ARE padded, and that padding is
    # load-bearing (1.24 == 1.24.0); do not assume the same of this one without re-measuring.
    x, y = (ea, na, pa, ka, sa), (eb, nb, pb, kb, sb)
    return (x > y) - (x < y)


_CLAUSE_RE = re.compile(r'^(>=|<=|==|=|<|>)\s*(\S+)$')


def in_range(ver, rng):
    """Is `ver` inside a GitHub Advisory `vulnerableVersionRange`? Clauses are ANDed.

    The grammar is bounded, not open: across 1122 real ranges harvested from 43 packages there
    are exactly FIVE forms -- '>= V, < V' (568), '< V' (368), '<= V' (111), '>= V, <= V' (57),
    and '= V' (18). An implementation that handled only '>=, <' would be silently wrong on the
    15% that use an INCLUSIVE upper bound or an exact pin, so every operator is evaluated rather
    than pattern-matched. Raises ValueError on anything unrecognized -- an unparseable range must
    never silently evaluate to "not vulnerable".
    """
    for clause in rng.split(','):
        clause = clause.strip()
        if not clause:
            continue
        m = _CLAUSE_RE.match(clause)
        if not m:
            raise ValueError(f'unparseable clause {clause!r} in range {rng!r}')
        op, v = m.group(1), m.group(2)
        c = vcmp(ver, v)
        if not {'>=': c >= 0, '<=': c <= 0, '<': c < 0,
                '>': c > 0, '=': c == 0, '==': c == 0}[op]:
            return False
    return True


# ---------------------------------------------------------------------------------------------
# Manifest parsing. Only EXACT pins are considered, because that is the whole point: a floating
# range is already dimension 18's existing finding, and reporting it here would double-count it.
# ---------------------------------------------------------------------------------------------

def parse_requirements(text):
    """`name==version` from a requirements.txt. Extras and markers are stripped."""
    out = []
    for raw in text.splitlines():
        line = raw.split('#')[0].strip()
        if not line or line.startswith('-'):
            continue
        line = line.split(';')[0].strip()        # environment markers
        # Trailing line continuation. `pip-compile`/`uv pip compile --generate-hashes` emit
        # `attrs==25.3.0 \` with the --hash lines following, and that is the MOST rigorously
        # pinned form of a requirements file -- exactly the population this probe most needs to
        # cover. Anchoring `$` straight after the version missed all 12 pins in a real file
        # (measured against a live VS Code extension manifest), which is a false negative in a
        # probe whose entire job is not to report an unearned clean. The --hash continuation
        # lines themselves start with `-`, so they are already skipped above.
        line = line.rstrip('\\').strip()
        m = re.match(r'^([A-Za-z0-9._-]+)\s*(?:\[[^\]]*\])?\s*==\s*([^\s,]+)$', line)
        if m:
            out.append((m.group(1), m.group(2)))
    return out


def parse_package_lock(text):
    """npm lockfile v2/v3 `packages` map, and the v1 `dependencies` tree."""
    out = []
    try:
        data = json.loads(text)
    except ValueError:
        return out
    for path, meta in (data.get('packages') or {}).items():
        if not path or not isinstance(meta, dict) or not meta.get('version'):
            continue
        name = meta.get('name') or path.split('node_modules/')[-1]
        if name:
            out.append((name, meta['version']))

    def walk(deps):
        for name, meta in (deps or {}).items():
            if isinstance(meta, dict):
                if meta.get('version'):
                    out.append((name, meta['version']))
                walk(meta.get('dependencies'))
    walk(data.get('dependencies') if not data.get('packages') else None)
    return out


def parse_package_json(text):
    """Only EXACT pins. `^1.2.3`/`~1.2.3`/`*` are ranges, so they are dimension 18's other
    finding, not this one -- picking them up here would report the same defect twice."""
    out = []
    try:
        data = json.loads(text)
    except ValueError:
        return out
    for key in ('dependencies', 'devDependencies', 'optionalDependencies'):
        for name, spec in (data.get(key) or {}).items():
            if isinstance(spec, str) and re.match(r'^\d+\.\d+', spec.strip()):
                out.append((name, spec.strip()))
    return out


MANIFESTS = (
    ('requirements.txt', 'PIP', parse_requirements),
    ('requirements-dev.txt', 'PIP', parse_requirements),
    ('package-lock.json', 'NPM', parse_package_lock),
    ('package.json', 'NPM', parse_package_json),
)


def discover(paths):
    """(ecosystem, name, version, manifest_path), deduped, vendored dirs pruned."""
    skip = {'.git', 'node_modules', '.venv', 'venv', 'dist', 'build', 'vendor', '__pycache__'}
    found, seen = [], set()
    for root in paths:
        if os.path.isfile(root):
            walk_iter = [(os.path.dirname(root) or '.', [], [os.path.basename(root)])]
        else:
            walk_iter = os.walk(root)
        for dirpath, dirnames, filenames in walk_iter:
            dirnames[:] = [d for d in dirnames if d not in skip]
            for fname, eco, parser in MANIFESTS:
                if fname not in filenames:
                    continue
                full = os.path.join(dirpath, fname)
                try:
                    with open(full, encoding='utf-8', errors='replace') as fh:
                        text = fh.read()
                except OSError:
                    continue
                for name, ver in parser(text):
                    key = (eco, name.lower(), ver)
                    if key not in seen:
                        seen.add(key)
                        found.append((eco, name, ver, full))
    return found


# ---------------------------------------------------------------------------------------------
# Advisory lookup
# ---------------------------------------------------------------------------------------------

GQL = """
query($eco: SecurityAdvisoryEcosystem!, $pkg: String!) {
  securityVulnerabilities(ecosystem: $eco, package: $pkg, first: 100) {
    nodes {
      advisory { ghsaId severity }
      vulnerableVersionRange
      firstPatchedVersion { identifier }
    }
  }
}
"""


def query_advisories(eco, pkg):
    """Advisory nodes for one package, or None if the LOOKUP ITSELF failed.

    None and [] are deliberately different values. [] means "asked, nothing known"; None means
    "could not ask" and must never be reported as a clean result.
    """
    try:
        proc = subprocess.run(
            ['gh', 'api', 'graphql', '-F', f'eco={eco}', '-F', f'pkg={pkg}',
             '-f', f'query={GQL}'],
            capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        return None
    if data.get('errors') or 'data' not in data:
        return None
    node = (data.get('data') or {}).get('securityVulnerabilities')
    if node is None:
        return None
    return node.get('nodes') or []


def match(version, nodes):
    """Advisories whose range contains `version`, deduped by GHSA.

    Dedupe is MANDATORY and must happen after range matching: the same GHSA is published against
    multiple branches with different ranges (GHSA-34jh-p97f-mpxf appears as both '< 1.26.19' and
    '>= 2.0.0, < 2.2.2'), so counting nodes instead of advisories inflates the finding count.
    """
    hits, unparseable = {}, []
    for n in nodes:
        rng = n.get('vulnerableVersionRange') or ''
        try:
            inside = in_range(version, rng)
        except ValueError as exc:
            unparseable.append(str(exc))
            continue
        if not inside:
            continue
        ghsa = ((n.get('advisory') or {}).get('ghsaId')) or '?'
        fixed = (n.get('firstPatchedVersion') or {}).get('identifier')
        prev = hits.get(ghsa)
        # Keep the LOWEST first-patched version across duplicate advisories: it is the nearest
        # upgrade that clears this finding, which is the actionable number for a reviewer.
        if prev is None or (fixed and prev.get('fixed') and vcmp(fixed, prev['fixed']) < 0):
            hits[ghsa] = {'ghsa': ghsa,
                          'severity': ((n.get('advisory') or {}).get('severity')) or '?',
                          'fixed': fixed, 'range': rng}
    order = {'CRITICAL': 0, 'HIGH': 1, 'MODERATE': 2, 'LOW': 3}
    return sorted(hits.values(), key=lambda h: (order.get(h['severity'], 9), h['ghsa'])), unparseable


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('-')]
    flags = [a for a in argv[1:] if a.startswith('-')]
    for f in flags:
        if f in ('-h', '--help'):
            sys.stdout.write(__doc__)
            return 0
        if f == '--self-test':
            return self_test()
        sys.stderr.write(f'{PROG}: unknown option {f}\n')
        return 2
    deps = discover(args or ['.'])
    if not deps:
        # Exit 2, NOT 0. "No manifests, so nothing pinned" and "everything pinned is safe" are
        # different results, and collapsing them into a pass is the silent zero this toolkit
        # exists to catch. field-coverage-scan.sh takes the same position for the same reason.
        sys.stderr.write('{}: no exact-pinned dependencies found in {}\n'.format(PROG, ', '.join(args or ['.'])))
        sys.stderr.write(f'{PROG}: nothing to check -- NOT a pass. Exit 2.\n')
        return 2
    findings, checked, failed = [], 0, []
    cache = {}
    for eco, name, ver, path in deps:
        key = (eco, name.lower())
        if key not in cache:
            cache[key] = query_advisories(eco, name)
        nodes = cache[key]
        if nodes is None:
            failed.append(f'{eco}/{name}')
            continue
        checked += 1
        hits, unparseable = match(ver, nodes)
        for u in unparseable:
            sys.stderr.write(f'{PROG}: WARNING {u} ({eco}/{name}) -- range not evaluated\n')
        if hits:
            findings.append((eco, name, ver, path, hits))
    if failed and not checked:
        sys.stderr.write(f'{PROG}: every advisory lookup failed ({len(failed)} packages). Is `gh` '
                         'installed and authenticated (`gh auth status`)?\n')
        sys.stderr.write(f'{PROG}: coverage is ZERO, not clean. Exit 2.\n')
        return 2
    for eco, name, ver, path, hits in findings:
        print(f'{path}:{name}=={ver}  [VULNERABLE-BUT-PINNED]')
        for h in hits:
            fixed = f"fixed in {h['fixed']}" if h['fixed'] else 'no fixed version published'
            print(f"    {h['ghsa']} {h['severity']:<8} vulnerable {h['range']} ({fixed})")
    n_adv = sum(len(h) for _, _, _, _, h in findings)
    print(f'\n{PROG}: {len(findings)} of {checked} pinned dependencies are pinned to a '
          f'known-vulnerable version ({n_adv} advisories).')
    if failed:
        # Partial coverage is stated, never rounded to a clean result (dimension 5).
        shown = ', '.join(failed[:8]) + ('...' if len(failed) > 8 else '')
        print(f'{PROG}: {len(failed)} lookup(s) FAILED and were not checked: {shown}')
        print(f'{PROG}: the result above is PARTIAL. Re-run before trusting a zero.')
    if not findings:
        print(f'{PROG}: this is a real negative for the packages checked, but it is bounded -- the '
              'GitHub Advisory DB only knows what has been reported, `ecosystem: ACTIONS` returns '
              'nothing so pinned CI actions are NOT covered, and transitive deps are covered only '
              'where a lockfile pins them.')
    return 1 if findings else 0


# ---------------------------------------------------------------------------------------------
# Offline self-test. Runs with no network and no gh, so it can gate in CI on every push.
# ---------------------------------------------------------------------------------------------

def _corpus_audit(rows):
    """(bad_parse, bad_invariant) over harvested advisory rows.

    A named function rather than a loop inlined in the self-test, deliberately: as an inline
    loop its invariant check could be mutated to `if False` and the whole self-test still
    passed -- a measured mutant survivor. Nothing tests a test unless the test's own logic is
    reachable, so this is extracted to be checkable against planted violations.
    """
    bad_parse, bad_inv = [], []
    for _eco, pkg, rng, fixed in rows:
        try:
            inside = in_range(fixed or '1.0.0', rng)
        except ValueError as exc:
            bad_parse.append((pkg, rng, str(exc)))
            continue
        if fixed and inside:
            bad_inv.append((pkg, rng, fixed))
    return bad_parse, bad_inv


def self_test():
    fails = []

    def ck(cond, label):
        if not cond:
            fails.append(label)

    # semver.org section 11, the normative precedence chain, verbatim.
    chain = ['1.0.0-alpha', '1.0.0-alpha.1', '1.0.0-alpha.beta', '1.0.0-beta',
             '1.0.0-beta.2', '1.0.0-beta.11', '1.0.0-rc.1', '1.0.0']
    # `zip(chain, chain[1:])`, not `itertools.pairwise`: pairwise is Python 3.10+, and this
    # script runs on whatever interpreter a reviewer happens to have. Dimension 6 (version
    # portability) applied to this skill's own code -- ruff's unsafe-fix rewrote it to
    # pairwise and it was reverted deliberately. noqa is narrow and carries its reason,
    # per CONTRIBUTING; do not widen it to a file- or repo-level exclude.
    for a, b in zip(chain, chain[1:]):  # noqa: RUF007
        ck(vcmp(a, b) == -1, f'semver11: {a} < {b}')
    # Multi-numbered pre-releases of the SAME word. This is the regression test for a bug the
    # oracle caught and an earlier version of this self-test did NOT: with 'b' ahead of 'beta' in
    # _PRE_RE the regex matches 'b', never consumes the '.8', and every beta collapses to one key.
    # Verified as a live mutant survivor before these three lines existed.
    ck(vcmp('3.0.0-beta.1', '3.0.0-beta.8') == -1, 'pre-release NUMBER compares: beta.1 < beta.8')
    ck(vcmp('5.0.0-alpha.0', '5.0.0-alpha.1') == -1, 'pre-release number: alpha.0 < alpha.1')
    ck(vcmp('13.3.1-canary.0', '13.3.1-canary.10') == -1, 'canary.0 < canary.10 (npm, unoracled)')
    # PEP440/semver spellings of the same pre-release must be EQUAL, which is what forces
    # 'a'/'b'/'c' to share a rank with 'alpha'/'beta'/'rc' rather than sorting alphabetically.
    ck(vcmp('5.0.0-beta.2', '5.0.0b2') == 0, 'beta.2 == b2 (both oracles agree)')
    ck(vcmp('1.0.0-rc.1', '1.0.0c1') == 0, 'rc.1 == c1')
    # PEP440 shapes, including the pre-release-sorts-before-release rule a naive compare inverts.
    ck(vcmp('2.6.0a1', '2.6.0') == -1, 'pep440: 2.6.0a1 < 2.6.0')
    ck(vcmp('24.7.0rc1', '24.7.0') == -1, 'pep440: rc before release')
    ck(vcmp('1.24', '1.24.0') == 0, 'zero-pad: 1.24 == 1.24.0')
    ck(vcmp('1.9', '1.10') == -1, 'numeric not lexical: 1.9 < 1.10')
    ck(vcmp('2.3.0.0', '2.3.0') == 0, 'four-segment equality')
    ck(vcmp('1!1.0', '2.0') == 1, 'epoch dominates')
    ck(vcmp('1.0.0+build1', '1.0.0') == 0, 'build metadata ignored')
    ck(vcmp('v1.2.3', '1.2.3') == 0, 'leading v stripped')
    # All five range forms measured in the real corpus.
    ck(in_range('1.24', '>= 1.23, < 2.7.0'), 'form >=,< : multi-clause AND')
    ck(not in_range('2.7.0', '>= 1.23, < 2.7.0'), 'form >=,< : upper bound exclusive')
    ck(in_range('2.4.0', '< 2.5.0'), 'form < ')
    ck(in_range('1.24.2', '<= 1.24.2'), 'form <= : INCLUSIVE upper bound')
    ck(not in_range('1.24.3', '<= 1.24.2'), 'form <= : just above')
    ck(in_range('1.18', '>= 1.17, <= 1.18'), 'form >=,<= : inclusive both ends')
    ck(in_range('3.1.0', '= 3.1.0'), 'form = : exact')
    ck(not in_range('3.1.1', '= 3.1.0'), 'form = : neighbour excluded')
    # An unparseable range must RAISE, never evaluate to "safe".
    try:
        in_range('1.0.0', '~> 1.0')
        fails.append('unparseable range must raise, not return False')
    except ValueError:
        pass
    # Dedupe by GHSA across per-branch advisories, keeping the lowest fix.
    nodes = [{'advisory': {'ghsaId': 'GHSA-dup', 'severity': 'MODERATE'},
              'vulnerableVersionRange': '< 1.26.19',
              'firstPatchedVersion': {'identifier': '1.26.19'}},
             {'advisory': {'ghsaId': 'GHSA-dup', 'severity': 'MODERATE'},
              'vulnerableVersionRange': '>= 0, < 1.30',
              'firstPatchedVersion': {'identifier': '1.30'}},
             {'advisory': {'ghsaId': 'GHSA-other', 'severity': 'CRITICAL'},
              'vulnerableVersionRange': '< 2.0',
              'firstPatchedVersion': {'identifier': '2.0'}}]
    hits, unp = match('1.25', nodes)
    ck(len(hits) == 2, f'dedupe by GHSA after range match (got {len(hits)})')
    ck(hits[0]['severity'] == 'CRITICAL', 'severity ordering: CRITICAL first')
    dup = next(h for h in hits if h['ghsa'] == 'GHSA-dup')
    ck(dup['fixed'] == '1.26.19', f"nearest fix kept, got {dup['fixed']}")
    ck(unp == [], 'no spurious unparseable')
    ck(match('9.9', nodes)[0] == [], 'version above every range is clean')
    # An unparseable range is reported and SKIPPED, and must not suppress a real sibling hit.
    hits2, unp2 = match('1.0', [{'advisory': {'ghsaId': 'G1', 'severity': 'HIGH'},
                                 'vulnerableVersionRange': '~> 1.0',
                                 'firstPatchedVersion': None},
                                {'advisory': {'ghsaId': 'G2', 'severity': 'LOW'},
                                 'vulnerableVersionRange': '< 2.0',
                                 'firstPatchedVersion': {'identifier': '2.0'}}])
    ck(len(unp2) == 1 and [h['ghsa'] for h in hits2] == ['G2'],
       'unparseable sibling does not suppress a real hit')
    # Manifest parsing: exact pins only.
    reqs = parse_requirements(
        'pyyaml==5.3\nrequests == 2.19.0  # comment\nurllib3>=1.24\n'
        'flask[async]==2.0.1\nboto3==1.0.0 ; python_version < "3.9"\n'
        '-r other.txt\n# whole-line comment\nnumpy\n')
    got = dict(reqs)
    ck(got.get('pyyaml') == '5.3', 'req: plain pin')
    ck(got.get('requests') == '2.19.0', 'req: spaces + trailing comment')
    ck(got.get('flask') == '2.0.1', 'req: extras stripped')
    ck(got.get('boto3') == '1.0.0', 'req: env marker stripped')
    ck('urllib3' not in got, 'req: >= is a RANGE, not this probe s finding')
    ck('numpy' not in got, 'req: unpinned ignored')
    # Hash-pinned `pip-compile --generate-hashes` output. Found as a live FALSE NEGATIVE against a
    # real manifest: all 12 pins were missed because the trailing ` \` defeated the `$` anchor.
    # This is the strictest pinning style that exists, so missing it meant reporting the
    # best-pinned repos as having nothing to check -- an unearned clean, the one outcome this
    # probe is built to prevent.
    hashed = dict(parse_requirements(
        'attrs==25.3.0 \\\n'
        '    --hash=sha256:427318ce031701fea540783410126f03899a97ffc6f61596ad581ac2e40e3bc3 \\\n'
        '    --hash=sha256:75d7cefc7fb576747b2c81b4442d4d4a1ce0900973527c011d1030fd3bf4af1b\n'
        '    # via cattrs\n'
        'jedi==0.19.2 \\\n'
        '    --hash=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'))
    ck(hashed.get('attrs') == '25.3.0', 'req: hash-pinned line continuation (real false negative)')
    ck(hashed.get('jedi') == '0.19.2', 'req: second hash-pinned pin also found')
    ck(len(hashed) == 2, f'req: --hash lines are not themselves pins (got {sorted(hashed)})')
    pj = dict(parse_package_json(json.dumps(
        {'dependencies': {'lodash': '4.17.20', 'express': '^4.17.1', 'ws': '~7.0.0'},
         'devDependencies': {'tar': '6.1.0'}})))
    ck(pj.get('lodash') == '4.17.20', 'pkg.json: exact pin')
    ck(pj.get('tar') == '6.1.0', 'pkg.json: devDependencies included')
    ck('express' not in pj and 'ws' not in pj, 'pkg.json: ^ and ~ are ranges, excluded')
    pl = dict(parse_package_lock(json.dumps(
        {'lockfileVersion': 3,
         'packages': {'': {'name': 'root'},
                      'node_modules/lodash': {'version': '4.17.20'},
                      'node_modules/a/node_modules/ws': {'version': '7.0.0'}}})))
    ck(pl.get('lodash') == '4.17.20', 'lock v3: packages map')
    ck(pl.get('ws') == '7.0.0', 'lock v3: nested transitive dep')
    pl1 = dict(parse_package_lock(json.dumps(
        {'lockfileVersion': 1,
         'dependencies': {'lodash': {'version': '4.17.20',
                                     'dependencies': {'ws': {'version': '7.0.0'}}}}})))
    ck(pl1.get('lodash') == '4.17.20' and pl1.get('ws') == '7.0.0', 'lock v1: nested tree')
    ck(parse_package_lock('{not json') == [], 'malformed lockfile does not crash')
    # discover(): vendored trees are pruned. Left untested, removing the prune passed the whole
    # suite -- and the consequence is not cosmetic: a repo with node_modules checked in would have
    # its own pins buried under thousands of third-party ones, every lookup burning an API call,
    # and findings reported against code the submitter does not ship. Measured mutant survivor.
    with tempfile.TemporaryDirectory() as td_disc:
        os.makedirs(os.path.join(td_disc, 'node_modules', 'left-pad'))
        with open(os.path.join(td_disc, 'requirements.txt'), 'w', encoding='utf-8') as fh:
            fh.write('pyyaml==5.3\n')
        with open(os.path.join(td_disc, 'node_modules', 'left-pad', 'package.json'), 'w',
                  encoding='utf-8') as fh:
            fh.write('{"dependencies": {"vendored-dep": "1.0.0"}}')
        names = {n for _e, n, _v, _p in discover([td_disc])}
        ck(names == {'pyyaml'},
           f'discover: vendored dirs pruned, first-party pin kept (got {sorted(names)})')

    # ---- Exit-code paths, exercised through main() ----
    # These matter more than any comparison above: this probe's whole value proposition is that it
    # never reports a clean result it did not earn. Both were live mutant survivors when the
    # self-test only covered the pure functions -- returning 0 for "no manifests" and treating a
    # failed lookup as "nothing known" both passed a 30-assertion suite. Structural coverage is
    # not behavioural coverage.
    import contextlib
    import io

    def quiet_main(argv):
        """main() with its report suppressed -- the exit CODE is what is under test here, and
        letting the reports through would bury a real self-test failure in sample output."""
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            return main(argv)

    with tempfile.TemporaryDirectory() as td:
        # No manifests at all must be exit 2, never 0. "Nothing to check" is not "checked, clean".
        empty = os.path.join(td, 'empty')
        os.makedirs(empty)
        ck(quiet_main([PROG, empty]) == 2, 'no manifests -> exit 2 (a silent zero if 0)')
        # A manifest whose deps are all UNPINNED is also exit 2: ranges are dimension 18's other
        # finding, so there is nothing for THIS probe to check.
        unp = os.path.join(td, 'unpinned')
        os.makedirs(unp)
        with open(os.path.join(unp, 'requirements.txt'), 'w') as fh:
            fh.write('requests>=2.0\nnumpy\n')
        ck(quiet_main([PROG, unp]) == 2, 'manifest with no exact pins -> exit 2')
        # A real pin present, but EVERY lookup fails: must be exit 2, and must not print a
        # clean bill of health. This is the network/auth-failure path.
        pinned = os.path.join(td, 'pinned')
        os.makedirs(pinned)
        with open(os.path.join(pinned, 'requirements.txt'), 'w') as fh:
            fh.write('pyyaml==5.3\n')
        real_query = globals()['query_advisories']
        try:
            globals()['query_advisories'] = lambda eco, pkg: None      # simulate lookup failure
            ck(quiet_main([PROG, pinned]) == 2, 'all lookups fail -> exit 2, not a clean 0')
            # Lookup succeeds and knows nothing: that IS a real (bounded) negative -> exit 0.
            globals()['query_advisories'] = lambda eco, pkg: []
            ck(quiet_main([PROG, pinned]) == 0, 'lookup OK, no advisories -> exit 0')
            # Lookup succeeds and the pin is inside a vulnerable range -> exit 1.
            globals()['query_advisories'] = lambda eco, pkg: [
                {'advisory': {'ghsaId': 'GHSA-test', 'severity': 'CRITICAL'},
                 'vulnerableVersionRange': '< 5.3.1',
                 'firstPatchedVersion': {'identifier': '5.3.1'}}]
            ck(quiet_main([PROG, pinned]) == 1, 'pinned-and-vulnerable -> exit 1')
            # And the same pin ABOVE the range is clean -> exit 0. Proves the exit 1 above came
            # from the range evaluation and not merely from an advisory existing.
            with open(os.path.join(pinned, 'requirements.txt'), 'w') as fh:
                fh.write('pyyaml==5.3.1\n')
            ck(quiet_main([PROG, pinned]) == 0, 'pin at the fixed version -> exit 0')
        finally:
            globals()['query_advisories'] = real_query
    # A failed subprocess must yield None, never [] -- the distinction the exit-2 path rests on.
    # `gh` is called with a deliberately invalid ecosystem, so this needs no network to fail.
    ck(query_advisories('NOT_AN_ECOSYSTEM', 'x') is None, 'failed lookup returns None, not []')
    # A GraphQL response carrying BOTH data and errors is the dangerous shape: rc is 0, the JSON
    # parses, and `securityVulnerabilities` may be present but truncated -- so the downstream
    # `node is None` fallback does NOT fire and a partial answer would be reported as complete.
    # Only the explicit `errors` check catches it, and that check survived mutation until this
    # case existed. Driven through a stub `gh` on PATH rather than by calling the real API.
    _path_gql = os.environ.get('PATH', '')
    with tempfile.TemporaryDirectory() as td_gql:
        stub = os.path.join(td_gql, 'gh')

        def _stub(body):
            with open(stub, 'w', encoding='utf-8') as fh:
                fh.write(f"#!/bin/sh\nprintf '%s' '{body}'\n")
            os.chmod(stub, 0o755)

        try:
            os.environ['PATH'] = td_gql
            _stub('{"data":{"securityVulnerabilities":{"nodes":[]}},'
                  '"errors":[{"message":"rate limited, results truncated"}]}')
            ck(query_advisories('PIP', 'pyyaml') is None,
               'data+errors (partial result) returns None, not a misleading []')
            # Negative control on the same stub mechanism: without `errors`, the same response
            # is a legitimate "asked, nothing known" and must come back as [] so a scan can
            # proceed. Without this row, "always return None" would pass the case above.
            _stub('{"data":{"securityVulnerabilities":{"nodes":[]}}}')
            ck(query_advisories('PIP', 'pyyaml') == [],
               'clean empty response returns [], distinct from a failure')
        finally:
            os.environ['PATH'] = _path_gql
    # `gh` MISSING ENTIRELY is a separate code path (OSError, not a non-zero exit) and it survived
    # mutation until this case existed. Exercised with a PATH containing no gh at all, which also
    # guarantees the self-test makes no outbound call: an empty PATH cannot resolve the binary.
    _path = os.environ.get('PATH', '')
    try:
        os.environ['PATH'] = ''
        ck(query_advisories('PIP', 'pyyaml') is None, 'gh absent (OSError) returns None, not []')
    finally:
        os.environ['PATH'] = _path

    # The real-corpus regression: every harvested range parses, and no firstPatchedVersion
    # falls inside its own vulnerable range. 736 independent facts from 43 packages.
    #
    # The audit function is itself checked against planted violations FIRST. Without these three
    # rows, disabling the invariant check left the entire self-test green -- the corpus looked
    # like 736 assertions while asserting nothing.
    ck(_corpus_audit([('PIP', 'p', '< 2.0', '1.5')])[1] != [],
       'corpus audit catches a planted invariant violation (fix inside its own range)')
    ck(_corpus_audit([('PIP', 'p', 'not-a-range', '1.5')])[0] != [],
       'corpus audit catches a planted unparseable range')
    ck(_corpus_audit([('PIP', 'p', '< 2.0', '2.0')]) == ([], []),
       'corpus audit negative control: a well-formed row is not flagged')
    here = os.path.dirname(os.path.abspath(__file__))
    corpus = os.path.join(here, 'test_pinned_vuln_data.json')
    if os.path.exists(corpus):
        with open(corpus, encoding='utf-8') as fh:
            rows = json.load(fh)['ranges']
        bad_parse, bad_inv = _corpus_audit(rows)
        ck(not bad_parse, f'corpus: all {len(rows)} ranges parse '
                          f'({len(bad_parse)} failed: {bad_parse[:3]})')
        ck(not bad_inv, f'corpus: no firstPatchedVersion inside its own range '
                        f'({len(bad_inv)} bad: {bad_inv[:3]})')
        print(f'{PROG}: corpus regression over {len(rows)} real advisory ranges')
    else:
        fails.append(f'corpus file missing: {corpus}')

    if fails:
        print(f'{PROG}: SELF-TEST FAILED ({len(fails)})')
        for f in fails:
            print(f'  - {f}')
        return 1
    print(f'{PROG}: self-test OK')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
