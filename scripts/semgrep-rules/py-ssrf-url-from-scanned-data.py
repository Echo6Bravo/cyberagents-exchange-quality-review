"""Planted-defect fixture for py-ssrf-url-from-scanned-data (dim 2/17, CWE-918, OWASP A01:2025).

Modelled on the shape this artifact class actually produces: a scanner reads cloud findings and then
fetches something named *in* those findings. `evidence_url` is attacker-influenceable in any
multi-tenant environment -- a resource tag, a webhook target, or a description field round-trips
through the provider API and comes back as a URL this tool will dutifully GET. Pointed at
169.254.169.254 it returns instance credentials; pointed at 127.0.0.1 it reaches admin ports that
have no authentication because they only ever expected localhost.

The must-NOT-match cases are enforced coverage, not decoration: `semgrep test` fails on any
unannotated line that fires, and each of the 8 exclusions in the .yaml was ablation-measured to be
load-bearing against one of these correct forms. Two of them (safe_constant_httpx,
safe_constant_generic_verb) exist specifically because the corresponding exclusions were INERT
without them -- an inert pattern that looks protective is worse than no pattern.

No credential-shaped literals anywhere: gitleaks scans full history in CI, so a fixture that trips it
is a permanent build failure that no later commit can undo. The metadata IP is written as a comment
rather than a request target for the same reason -- nothing here should look like a live SSRF PoC.
"""

import urllib.request
from urllib.parse import urlparse

import httpx
import requests

# Named constants, not inline literals, so the Gate 5 mutation table can target each vulnerable line
# by a string that occurs exactly ONCE in this file. A mutation `old` string appearing twice silently
# mutates the wrong line, and the failure then reads as a rule problem rather than a table problem.
ALLOWED_HOSTS = {"cloud.tenable.com"}
STATUS_URL = "https://cloud.tenable.com/status"
TIMEOUT = 10


def vuln_url_from_finding(finding):
    """VULNERABLE: the URL is whatever the scanned data said it was."""
    # ruleid: py-ssrf-url-from-scanned-data
    return requests.get(finding["evidence_url"], timeout=TIMEOUT).json()


def vuln_host_interpolated(host, finding_id):
    """VULNERABLE: f-string host. Still fires -- the literal-URL exclusions are
    interpolation-sensitive, which is the whole point of measuring them."""
    # ruleid: py-ssrf-url-from-scanned-data
    return requests.post(f"https://{host}/api/v1/findings/{finding_id}", json={}, timeout=TIMEOUT)


def vuln_urlopen(finding):
    """VULNERABLE: stdlib spelling. bandit raises B310 here -- but also on
    safe_constant_urlopen() below, which is why B310 is not coverage for this question."""
    # ruleid: py-ssrf-url-from-scanned-data
    return urllib.request.urlopen(finding["evidence_url"]).read()


def vuln_httpx(finding):
    """VULNERABLE: httpx spelling. bandit does not cover httpx at all."""
    # ruleid: py-ssrf-url-from-scanned-data
    return httpx.get(finding["callback"], timeout=TIMEOUT)


def safe_allowlist_negative_form(finding):
    """OK: hostname checked against an allowlist before the request.

    Note for reviewers: this is the spelling the rule was first written against, and it is still
    only a LEXICAL guard as far as semgrep is concerned. It does not stop an allowlisted host from
    redirecting to 169.254.169.254 -- `requests` follows redirects by default. Passing
    allow_redirects=False is the missing half, and no pattern here can tell you whether you did.
    """
    url = finding["evidence_url"]
    host = urlparse(url).hostname
    if host not in ALLOWED_HOSTS:
        raise ValueError("host not permitted")
    return requests.get(url, timeout=TIMEOUT).json()


def safe_allowlist_positive_form(finding):
    """OK: the same guard written the other way round. A FALSE POSITIVE before this was handled."""
    url = finding["evidence_url"]
    if urlparse(url).hostname in ALLOWED_HOSTS:
        return requests.get(url, timeout=TIMEOUT).json()
    return None


def safe_allowlist_assert_form(finding):
    """OK: assert-form guard. A FALSE POSITIVE before this was handled.

    Weakest of the three spellings: `python -O` strips the assert, so in an optimized build this
    allowlist does not run. Accepted because it is lexically a guard; dimension 11 challenges it.
    """
    url = finding["evidence_url"]
    assert urlparse(url).hostname in ALLOWED_HOSTS
    return requests.get(url, timeout=TIMEOUT).json()


def safe_constant():
    """OK: hardcoded URL, so no scanned data reaches it."""
    return requests.get(STATUS_URL, timeout=TIMEOUT).json()


def safe_constant_urlopen():
    """OK: hardcoded URL via stdlib. bandit still raises B310 on this correct line."""
    return urllib.request.urlopen("https://cloud.tenable.com/status").read()


def safe_constant_httpx():
    """OK: hardcoded URL via httpx. Exists because the httpx literal exclusion was INERT without
    it -- see the .yaml header."""
    return httpx.get("https://cloud.tenable.com/status", timeout=TIMEOUT).json()


def safe_constant_generic_verb():
    """OK: hardcoded URL through the generic verb API. Exists because the
    requests.request literal exclusion was INERT without it."""
    return requests.request("GET", "https://cloud.tenable.com/status", timeout=TIMEOUT).json()
