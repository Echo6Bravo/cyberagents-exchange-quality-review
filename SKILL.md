---
name: cyberagents-exchange-quality-review
description: >-
  Adversarial pre-submission quality gate for cybersecurity agents/skills/MCP servers,
  especially those bound for the Tenable CyberAgents Exchange. Systematically hunts the
  failure classes that hurt a customer — detection false-negatives, injection/XSS, messy-data
  robustness, scale limits, operational behavior, version portability, schema drift, leaked
  secrets (full git history), malicious/offensive behavior, undisclosed outbound calls,
  LLM/AI-specific risks, and execution-scope correctness in generated artifacts — and reports
  findings ranked by severity BEFORE any public/Exchange push. Runs a standard toolkit (gitleaks, ruff, bandit, semgrep, shellcheck, actionlint, CodeQL) and
  mirrors the live Exchange reviewer checklist. Use before shipping, submitting, or when asked
  "is this enterprise-ready / did we miss anything?".
---

# Quality review — a pre-submission gate for CyberAgents Exchange work

**Invocation:** run a quality review on this repo (or `/cyberagents-exchange-quality-review`).

A repeatable adversarial pass. The goal is to find, up front, the issues that would otherwise
surface after "done." Run every dimension, report findings ranked most-severe first, each with
a concrete repro and fix. Do NOT rubber-stamp: if a dimension is genuinely N/A for the
artifact, say why.

For each dimension, actually TEST it (write a probe, feed adversarial input, run a container)
rather than reasoning about it. **Prefer proof over assertion.**

> **The Exchange checklist is authoritative and changes.** The "For Tenable CyberAgents
> Exchange submissions" section below mirrors `tenable/cyberagents-exchange`
> `docs/contributing_checklist.md` and `validator.py` as of this skill's writing. Always
> **fetch the live versions** at review time and treat them — not this copy — as the source
> of truth. This skill is a community contribution and is **not** an official Tenable tool or
> an assurance of acceptance.

## Preflight — declare the coverage level BEFORE reviewing
First, check which scanners are available and tell the user the resulting coverage, so the
verdict is never trusted beyond what actually ran. Run `bash setup.sh --check` if the repo has
it, else probe directly:
```bash
for t in gitleaks ruff bandit shellcheck actionlint semgrep; do
  command -v "$t" >/dev/null 2>&1 && echo "present: $t" || echo "MISSING: $t"
done
```
**`semgrep` present is NOT semgrep coverage.** It ships no bundled security rules, so an install
with no rules contributes nothing. Report it as three states: MISSING / present-but-no-rules
(**counts as MISSING for coverage**) / present with `scripts/semgrep-rules`. Do **not** try
`--config p/<pack>` to find out: the registry fetch has no bounded timeout and can hang for
minutes on a TLS-intercepting network. Check for the rules directory instead.
Then state, up front, something like: *"Running with gitleaks+ruff+bandit present; shellcheck
and actionlint MISSING → the shell and workflow dimensions run in degraded (manual) mode."*
Offer to install missing tools (`bash setup.sh`, or `brew install …` / `pipx install bandit`)
— but **only with the user's approval**; never assume you may install software. If a tool
stays missing, run that dimension's documented fallback and **label the finding "degraded —
<tool> not available"** so the gap is visible. CodeQL is a GitHub-Actions workflow on the
target repo, not a local install (see the toolkit note).

**Shipped helper scripts — run them WHEN THEIR PRECONDITIONS HOLD; skip-with-a-note otherwise.**
Every script in `scripts/` is part of the review by default, but only when it applies — forcing a
tool that doesn't fit is exactly the overreach this skill warns others against (dim 3: degrade
gracefully).
Decide per target, and state the decision out loud like any other coverage call:
- **`scripts/empty-relationship-scan.sh <target>` (dimension 1).** Run it **if** the target has
  source in a supported language (`.py/.js/.ts/.jsx/.tsx/.go/.rb/.sh/.java`). Triage every hit as
  a *question* (read the code; is a missing/empty value excluded or silently passed?), not a
  confirmed bug. If the language isn't covered or it flags nothing, **say so and note it is not
  proof of safety** — still write the real empty-input test. Cheap (grep-only); default to running
  it whenever any supported source exists.
- **`scripts/tautology-scan.sh <target>` (dimension 11).** Run it **if** the target ships tests in
  `.py/.js/.ts/.jsx/.tsx/.rb`. It greps *test files only* for assertions carrying an
  `or not <precondition>` escape hatch — the shape `mutation-check.sh` structurally cannot find,
  because no mutation to the code under test changes the outcome. Triage every hit as a *question*
  (is the right-hand side false in the fixture? then the left-hand claim never ran). Cheap
  (grep-only); default to running it whenever test files exist. It is **line-based**: a wrapped
  `or not` continuation and any assertion over a *derived* property are invisible to it, so zero
  hits is not proof — see dimension 11.
- **`scripts/field-coverage-scan.sh <target>` (dimension 2).** Run it **if** the target has Python
  models with annotated fields *and* any hostile-value tests. It diffs the string fields the code
  declares against the fields a hostile test actually names, because the failure worth hunting is a
  thorough payload set applied to **one field** — which is how a real arbitrary-file-write shipped
  past a suite of 24 injection payloads that all landed on the field the checklist pointed at.
  Triage every uncovered field as a *question* ("does anything untrusted reach this, and to which
  sink?"); many are legitimately fine. Python-only and `str`-only by design, and it **cannot** tell
  you whether a payload suited the field's sink — the case that actually shipped reads as covered.
  It exits 2 rather than 0 when there are no models or no hostile tests to compare, so a clean run
  is never manufactured out of having found nothing.
- **`scripts/pinned-vuln-scan.py <target>` (dimension 18).** Run it **if** the target ships a
  `requirements.txt`, `package.json`, or `package-lock.json` *and* `gh auth status` succeeds. It
  checks every exact pin against the GitHub Advisory DB, because reviewing whether deps are
  **pinned** says nothing about whether they are **safe** — a pin reproduces whatever it was and
  never drifts onto a fix. Report a hit as a **defect citing the GHSA id and the advisory's own
  severity** (the cite-your-basis rule), not as a rejection gate. Two results are not passes:
  **exit 2** means it could not complete (no manifests, no exact pins, or every lookup failed) and
  must never be read as clean, and even exit 0 is a **bounded** negative — `ecosystem: ACTIONS`
  returns nothing, so **pinned CI actions need a manual check**, and transitive deps count only
  where a lockfile pins them. Range specifiers (`^1.2.3`) are excluded on purpose: they are the
  not-pinned finding, which the same dimension already covers, so a hit is never counted twice.
- **`scripts/mutation-check.sh` (dimension 11).** For each regression test backing a fixed finding,
  run it to prove the test FAILS on revert — **only if all preconditions hold:** (a) a runnable
  test command exists; (b) it is fast and **side-effect-free** (no live tenant/API token, no
  network, no paid calls, no state mutation); (c) the suite is green to begin with; (d) the target
  working tree is clean (it edits a file in place and restores via trap, so a dirty tree adds
  risk). If any precondition fails — slow/networked/absent tests, dirty tree, nothing fixed to
  guard — **do NOT force it**: note that the guard was verified by reasoning, not mechanically, and
  say which precondition blocked it. Never fabricate a test command just to run it.

Treat each like the scanners above: its absence or non-applicability is a *labeled coverage gap*,
never a silent skip and never a reason to overstate what was checked.

## Standard toolkit — RUN these, don't eyeball
Run whatever of these the language/stack supports; treat findings as input to the relevant
dimension, not a substitute for it. Install only with the user's approval (`bash setup.sh`).
- **Secrets:** `gitleaks git --no-banner --redact .` over **full history** (fetch-depth 0 in CI).
- **Python lint/SAST:** `ruff check .` and `bandit -r .`. Don't **select** ruff's `S`
  (flake8-bandit) rules — they are a port of bandit's checks (`S501` ≡ `B501`), so enabling the set
  would report every Python security finding twice and inflate the count. `bandit` owns that lane.
  **But do not claim the `S` rules are off, because a few are on by default:** measured on ruff
  0.16.1, the default set already includes `S102`/`S110`/`S112`, so `try/except/pass` is reported by
  both tools with no `select` at all. When you dedupe a finding count across these two tools, dedupe
  on the *shape*, not on the assumption that their rule sets are disjoint.
  B101 (assert) is commonly skipped
  because asserts in *tests* are intentional — scope the skip to tests rather than suppressing
  it repo-wide. In library/runtime code an `assert` is **not** a guard: `python -O` strips it,
  so an assert-protected invariant is unenforced in exactly the optimized build where violating
  it does damage. Any assert that validates external input or protects a security decision is a
  finding; raise a real exception instead.
- **Cross-language patterns:** `semgrep scan --config scripts/semgrep-rules --metrics=off
  --disable-version-check <target>`. **Only ever this skill's own rules** — never `--config p/<pack>`
  (the hosted registry is not part of this toolkit and the fetch can hang for minutes behind a TLS
  proxy). Its job is the languages `ruff`/`bandit` don't reach — **JS/TS especially**, which matters
  because many Exchange listings are TypeScript MCP servers. It is **additive, never a replacement**:
  where `bandit` already covers a Python shape (e.g. `verify=False` = B501), the rule set
  deliberately has no rule, so a duplicate finding is a bug in the rules, not a second opinion. The
  two flags are not optional — without them a blocked version check adds ~90s per invocation.
  If the rules directory is absent, semgrep contributes **nothing**; say so rather than listing it
  as a tool that ran.
  **Bound the claim to the rules that exist.** The set covers dimensions 2, 3, 6, 8, 11, 13, and 17 —
  not "JS/TS security." Twelve rules, each with a documented blind-spot list in its own header; read the
  header of any rule you cite before quoting it, because several deliberately trade recall for a hit
  list a human will read (`ts-weak-hash-or-random` ignores bare `Math.random()`; `ts-binds-all-interfaces`
  cannot see `listen(port)` with no host at all, which is the *commonest* real exposure).
  **Report a zero against the corpus that produced it.** Measured on 1138 real JS/TS files: three of
  these rules found nothing because that corpus contains **no instances of what they look for** — a
  true negative with no discriminating power. "0 false positives" from such a run is an overclaim of
  exactly the kind dimension 12 exists to catch; say "validated on planted-defect fixtures only."
  **Then check whether the construct is present before believing the zero — a zero can be a blind spot
  in the rule.** Re-measuring the TS rules against 1074 TypeScript files from six real MCP servers
  turned one of those comfortable zeros into a rule defect. `ts-binds-all-interfaces` reported nothing
  even though the corpus held 102 `.listen(` calls and 17 files mentioning `0.0.0.0`; the cause was
  that modern MCP servers bind via a framework *factory* (`createMcpExpressApp({ host: "0.0.0.0" })`),
  which the receiver-bound `$A.listen(...)` pattern could not match. It missed 8 real sites. The
  three-question drill: does the rule fire on its own fixture (yes — so it is not broken), does the
  target construct appear in the corpus (yes — so the corpus is not empty), and if both, **why is the
  count zero?** Skipping the third question is this skill's own dimension 1, applied to its tooling.
  **Expect wildcard CORS on MCP servers and triage intent, not presence.** That corpus produced 13
  `ts-wildcard-cors` hits, 8 in production paths — the highest-firing rule of the set, and every hit
  genuine. Cross-origin access to OAuth metadata and token endpoints is close to a house style there.
  Sort hits into deliberate-and-reasoned (a comment explains why web clients need the origin),
  deliberate-and-self-flagged (`// use "*" with caution in production`), and unremarked-on-a-tool-
  endpoint. Only the third is usually worth raising, and reporting all three as one number is noise.
  **A rule can be right about the construct and still find the one thing that matters.** The same run
  produced 3 `ts-weak-hash-or-random` hits; two were cache-key uniquifiers, and one was `Math.random()`
  minting the **`jti` replay-protection claim** of a private-key-JWT client assertion in the official
  MCP TypeScript SDK — in a function that had already verified `globalThis.crypto` was available. A
  low-precision rule still needs every hit read, because the hit that matters sits in an auth path.
  **Scope N/A honestly by surface.** `ts-token-in-localstorage` found nothing across all 1074 files
  because a Node MCP server has no DOM and calls no web-storage API at all. On a submission with no
  browser surface that rule is **N/A, not passed** — "no credential-storage issues found" after
  scanning only a server is the dimension 12 overclaim in miniature.
  **Scope the scan to first-party source when you can.** All 16 `ts-unsafe-deserialization` hits in
  that measurement were in *vendored* libraries (prototype.js, YUI, socket.io, ace) — real `eval`
  calls, correctly flagged, and all the same already-known fact about code the submitter did not write.
  A finding count inflated by a vendored bundle makes a review look deeper than it is.
  **A clean zero from a test-scoped rule is meaningless until you override the built-in ignore
  list.** Semgrep's bundled `.semgrepignore` excludes `tests/` by default and announces it only on
  **stderr** — the JSON `paths.skipped` array stays empty and the exit code stays 0, so a
  test-quality rule reports "no findings" against a repo full of them. Measured on 1.172.0: naming
  the test **directory** as an extra target does **not** help in a git repo (the git-tracked-files
  filter drops it again), and `--no-git-ignore`, `--project-root`, and `--novcs` do not help
  either. Two things do work — pick by whether you may write to the target:
  name the test **files** explicitly as extra targets (`... <target> <target>/tests/test_a.py`),
  which bypasses it where directories do not; or put an empty `.semgrepignore` in the target's own
  root, which is only appropriate on a repo you own. Either way **read stderr for
  `Files matching .semgrepignore patterns: N`** and report a nonzero N as reduced coverage, not as
  a clean result.
- **Shell:** `shellcheck -S warning` on every `*.sh`.
- **GitHub Actions:** `actionlint` on every workflow (catches invalid inputs before a failed run).
- **Deep SAST:** **CodeQL** — best run as a GitHub Actions workflow (`github/codeql-action`,
  `security-and-quality` suite, free for public repos, results in the Security tab). The CLI
  often can't fetch query packs behind a corporate TLS proxy, so prefer the Action. Triage
  alerts by security-severity; low-severity style notes are fixed or justified, not ignored.
- **Test-guard proof (this skill ships it):** `scripts/mutation-check.sh` proves a regression
  test actually catches the bug it claims to — runs the test clean, mutates the guarded file,
  requires the test to FAIL, then restores. Use it on the tests added for any fixed finding
  (dimension 11). Language-agnostic; the test command's exit code is the signal.
- **Empty/absent-relationship smell (this skill ships it):** `scripts/empty-relationship-scan.sh`
  is a heuristic grep for `LOOKUP.get(k) or set()`-style fallthroughs that can leak a
  missing relationship past a gate (dimension 1). Hits are questions, not confirmed bugs.
- **Vacuous-assertion smell (this skill ships it):** `scripts/tautology-scan.sh` is a heuristic grep
  over *test files* for `assert … or not <precondition>` escape hatches — assertions that pass
  without evaluating their real claim (dimension 11). Complements `mutation-check.sh`, which cannot
  detect this shape. Hits are questions; zero hits is not proof (it misses wrapped continuations
  and derived-property assertions).
Every one of these should also be a **CI gate** so it can't regress (see dimension 11).

## Dimensions (in priority order — customer-impact first)

1. **Detection correctness — false NEGATIVES (highest priority for a security tool).**
   Does any real, in-scope finding get silently dropped? Check allow-lists/keep-lists for
   coverage gaps; confirm the tool SURFACES unknowns for review rather than discarding them.
   Probe with inputs the maps don't explicitly know about.
   - **Cross-variant probe (a top silent-zero class) — reviewer judgment + live run, not
     scriptable.** When a filter/query/parser is parameterized by an enum-like axis — cloud
     provider, region, OS family, resource type, identity kind — exercise **more than one value
     of that axis against the real system**. A predicate that is correct for one value and
     silently returns **empty** for the others (e.g. a field that only coincides across providers
     for one cloud) passes every test for the value you tried while dropping whole populations.
     "Works for the provider/variant I tested" is not "works."
   - **Empty/absent-relationship probe.** Feed inputs where a required join/relationship is
     *missing* (host with no endpoint, finding with no CVE, resource with no identity), not just
     present-but-wrong, and confirm the missing case is excluded/surfaced — not leaked because an
     empty value silently satisfied a gate. `scripts/empty-relationship-scan.sh` is a **heuristic
     smell-finder** for this shape (`x = LOOKUP.get(k) or set()` feeding a gate); every hit is a
     question to answer by reading the code, and zero hits is NOT proof — still write the actual
     empty-input test.

2. **Input safety — injection/XSS/path traversal.** Every value sourced from the scanned
   environment (names, IDs, components, free text) that reaches HTML/SVG/CSV/shell/SQL/**a
   filesystem path** must be escaped/parameterized/**contained** for its sink. Prove it: inject
   `<script>`, attribute-breakout, and formula-injection payloads into every field and verify
   (DOM-level / parser-level) that nothing executes.
   CodeQL's taint queries are the automated backstop — but the payload-injection probe is the
   primary proof; don't rely on the scanner alone.
   *Deserialization is the same class with a different sink:* untrusted input that becomes **code or
   an object graph**. `bandit` owns the Python constructs (B301 `pickle.loads`, B506 unsafe
   `yaml.load`) — **when it is installed**, which is optional here, so credit that coverage
   conditionally and label it degraded when absent. `semgrep-rules/ts-unsafe-deserialization` covers
   the TS side. One thing to check before believing a clean YAML result: in **js-yaml v4** bare
   `yaml.load(text)` is safe, but in **v3** it is not — read the pinned version in `package.json`,
   because the rule matches an explicit unsafe `schema:` and stays silent on v3's unsafe default.
   - *A path is a sink.* A value that becomes part of a **path** — a filename, a directory, an
     archive entry, a storage key — is as much a sink as one that becomes shell, and its payloads
     are different: `../`, a leading `/`, `..` as a whole segment, a NUL, a trailing separator, a
     symlink target. **The correct validator for a shell or SQL sink is usually the WRONG one for
     a path sink:** identifier allowlists routinely permit `/` because real cloud identifiers
     require it. Assert containment on the **resolved** path
     (`Path.resolve().is_relative_to(out_dir)`) as the last statement before the write — never
     deduce it from upstream validation, because that deduction breaks silently the first time
     someone adds a path component nobody re-validated. `bandit` does not raise this shape at any
     severity, so "the scanners are clean" is not evidence here.
   - *A URL is a sink, and it is the one this artifact class gets wrong.* A value that becomes part
     of an **outbound request target** — a URL, a hostname, a webhook, a callback, a redirect
     target — is a sink (`CWE-918`, SSRF). It matters here more than in most software because the
     job of these tools is to read attacker-influenceable cloud metadata and then go fetch things:
     a resource tag, a description, or an `evidence_url` round-trips through the provider API and
     comes back as something the tool will dutifully GET. Pointed at the instance-metadata endpoint
     (`169.254.169.254`) it returns the tool's own credentials; pointed at `127.0.0.1` it reaches
     admin ports that have no authentication because they only ever expected localhost. Parse the
     URL and assert the **hostname** against an allowlist immediately before the request — a scheme
     check, a `startswith`, or a substring test is not an allowlist. Then ask the question the
     allowlist does not answer: **an allowlisted host can redirect to a blocked one**, and
     `requests` follows redirects by default, so `allow_redirects=False` (or a re-check on the final
     URL) is the missing half. `semgrep-rules/py-ssrf-url-from-scanned-data` is the backstop.
     `bandit` B310 is **not** coverage for this: it audits the *scheme* on `urlopen`, fires on
     correct constant-URL code too, and does not cover `requests` or `httpx` at all — so "bandit is
     clean" says nothing about where a URL came from.
   - *Ask which FIELDS the payloads reached, not just which payloads exist.* The failure mode worth
     hunting is a thorough payload set applied to one field. Run
     `scripts/field-coverage-scan.sh <target>` (dimension 2's payload-coverage probe) to diff
     declared string fields against the fields any hostile test actually names; triage each
     uncovered field as a question. It cannot tell you whether a payload *suited* the field's sink —
     that judgement stays here, and it is the part that fails in practice.
   - *A safety comment that clears one component is a reason to look harder, not coverage.* Where a
     comment argues a specific component is safe, enumerate **every** component that reaches the
     sink and check each: a comment proving `cloud` cannot escape, silent about the `account_id` and
     `region` interpolated into the same string, stops the next reader from checking the siblings —
     worse than no comment. The fix is usually to replace the argument with an assertion, which
     cannot be true of only one component.
   - Severity note: an arbitrary file write reachable from tool input data is **Critical**
     (`CWE-22`) under the existing "harm to the user or a third party" basis, regardless of what the
     scanners say.

3. **Robustness on messy data AND messy invocation.** Two surfaces, same bar — fail cleanly
   with an actionable message (never a raw stack trace) or degrade gracefully, and verify the
   exit-code contract on both.
   - *Data plane:* null/missing fields, wrong types, duplicates, empty result sets,
     truncated/interrupted inputs, malformed pages.
   - *Invocation plane (often the neglected one):* every entry point an operator or scheduler
     drives — CLI args, flags, env vars, config files. Probe missing/extra/reordered args, a
     non-existent or unreadable input file, a non-numeric value where an int is expected, an
     empty/`--help`-only call. A tool whose data path is hardened but whose argument parser
     throws `IndexError`/`FileNotFoundError`/`ValueError` on bad input still fails the
     dimension. **Probe each entry point, not just the happy-path one covered by tests** —
     the invocation the test suite never calls is exactly where the raw traceback hides.
   - *Failing cleanly is only half the dimension — the other half is failing CLOSED.* Everything
     above asks whether an error surfaces well. Ask the opposite too: when the handler runs, does it
     hand the caller a **permissive** value? A scanner that returns `True` for "compliant", or `[]`
     for "findings", when its input failed to parse has reported a clean bill of health for an
     environment it never examined — and the caller cannot distinguish that from a real pass. This is
     **more dangerous than the crash**, because a crash gets noticed; this ships a green dashboard
     indefinitely. The tell is a log line followed by a permissive return: the `log.warning()` is
     what convinces the author they handled it. Prefer failing closed (`raise`, or return `False`),
     and better still return a **third state the caller must handle** (`UNAVAILABLE`, or `None` with
     a `checked` flag) so "did not run" can never render as "passed" — note that plain fail-closed
     still conflates "not compliant" with "could not check", which is its own reporting defect.
     `semgrep-rules/py-failopen-on-exception` is the backstop for the Python shapes. It is additive,
     not duplicative: `bandit` B110 sees only `try/except/pass` (one of the three shapes), and
     `ruff` BLE001/S110 flag the *style* of a blind except — none of them distinguish a fail-open in
     a security decision from a benign one, which is the entire question. It also cannot: a
     `return []` that legitimately means "no cached rows" is a finding to triage, not a defect, and
     permissive `{}`/`0`/`None` returns are outside the rule's reach.
   - *Would a silent partial failure look identical to a clean result?* (OWASP A09, and the rename
     from "logging failures" is the useful part.) Two questions, in order. **Reconstruction:** from
     the tool's own output and logs alone, can you tell what it actually scanned — which accounts,
     regions, resource types, and crucially which ones it *skipped* and why? A run that examined 3
     of 40 accounts because 37 credentials expired must not be reportable as "3 findings". State the
     denominator, not just the numerator. **Surfacing:** does anything make a degraded run *visible*
     — a nonzero exit code, a `[DEGRADED]` marker in the output, a summary line naming the skipped
     units — or does it require someone to read stderr they will never read? Scheduled tools are the
     sharp case: nobody reads the logs of a job that exits 0. This is prose-only and stays that way;
     "sufficient logging" has no construct signature, so no rule can answer it. Where the tool
     tolerates partial failure by design (dimension 5), this is the check that the tolerance is
     *reported* rather than merely survived.

4. **Scale.** Estimate volume at 10–50x the test environment (pull size, memory, output size,
   algorithmic complexity). Confirm caps/streaming/chunking exist and that nothing is silently
   truncated. Extrapolate output size; open the result. **Is the code path used AT SCALE the one
   that was actually tested?** Large-input handling (chunking, pagination, per-shard scoping,
   streaming) is frequently a *separate* path from the small-input path the tests exercise — so
   it can be entirely broken while every test is green. Exercise the scale path itself (e.g. a
   small budget/chunk size that *forces* chunking), not just a big input through the small path.
   - **Fixed-text amplification — measure bytes *per item*, at two scales, not total bytes.**
     For anything that emits per-item output (reports, remediation scripts, IaC, findings
     files), the dominant cost is often not the item but the boilerplate around it: a header,
     an explanation, a caveat paragraph re-emitted once per item instead of once per group or
     once per run. Render at two sizes (e.g. 1k and 10k items) and compare **bytes/item**. If
     it stays flat, fixed text dominates and output is needlessly linear in items × prose; if
     it falls, shared text is being amortized. Real case: ~68% of a generator's output bytes
     were comment lines, with a per-policy block emitted once per *resource* — 587 times for 5
     distinct policies — and a how-to header repeated in all 159 files. Hoisting run-level text to a
     companion README and grouping per policy cut bytes/item 14% at 1k items and 48% at 50k.
     **That the saving grows with scale is the signal, and it is why one measurement cannot
     tell you anything** — at 1k the fix looks marginal; the same fix is transformative at 50k.
     Measure before *and* after on the *same* input distribution, and compare like with like
     (per-item body against per-item body); mixing in run-level files or re-generating the
     input between runs produces a flattering number that will not survive review.
     **Hoist by consequence, not by length:** reference detail (summary, prerequisites, docs
     links) can move to a companion file, but anything a reader must see *before acting* —
     irreversibility, cost, blast radius — stays inline next to the thing it warns about. A
     warning in a sibling file is a warning that gets skipped.
     **Bucket: Informational by default** — verbose output is waste, not a defect. Move it into
     Defects (and only then give it a severity) with the consequence named: it breaches a
     documented limit, it exhausts a real resource at the tool's claimed scale (disk, memory, a
     paid token budget, a rate limit), or the volume itself defeats review so changes ship
     unexamined. "It could be smaller" is Informational; report it, don't block on it.

5. **Operational.** Exit codes a scheduler can branch on; partial-failure tolerance (one unit
   fails → flag the gap, don't lose everything); API retry/backoff on 429/5xx; determinism/
   reproducibility for audit.

6. **Version portability & transport security.** Language/runtime floor (test on the real
   minimum, e.g. a container); avoid tool flags newer than the documented floor (e.g.
   `curl --fail-with-body` needs 7.76+). No unpinned/absent third-party deps assumed present.
   **TLS must be verified** on all outbound traffic — never `CERT_NONE`/`verify=False`/
   `-k`, especially on requests carrying a credential (a silent MITM/credential-exposure bug).
   `bandit` catches the Python form (B501) when installed; `semgrep-rules/ts-tls-verification-disabled`
   catches the Node/TS one (`rejectUnauthorized: false`), which nothing else in the toolkit can parse.
   Neither sees `NODE_TLS_REJECT_UNAUTHORIZED=0` in an env file, Dockerfile, or workflow — the more
   common form in a containerized MCP server, and a plain grep away.

7. **Schema/contract drift.** If the tool depends on an external schema (UDM/GraphQL/API), is
   there a canary that fails loud when a depended-on field is renamed/removed, rather than
   returning empty?

8. **Secrets & data hygiene.** No token/credential/real-assessment-data in tracked files, in
   command lines, or in the transcript. **Scan the FULL git history, not just the working tree**
   — a secret committed and later deleted still lives in history and still fails. RUN
   `gitleaks git --no-banner --redact .`; else `git log -p | grep -nE '(gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-|-----BEGIN [A-Z ]*PRIVATE KEY-----|_TOKEN=[A-Za-z0-9]{12,})'`.
   `.gitignore` blocks secrets + real data; only synthetic samples are committed. Any leak =
   rotate the credential AND purge it from history (BFG/filter-repo) before shipping.
   **Also check credential storage AT REST:** a user-supplied API key/token must live in an OS
   keystore / secret manager / vetted AEAD — never plaintext in a local DB or `config.json`,
   never browser `localStorage`/`chrome.storage.local`, never a home-rolled XOR scheme, and
   never passed on a command line (leaks to `ps`/shell history).
   **And check how the credential was MADE, not only where it is kept.** A token minted from
   `Math.random()` is guessable regardless of how well it is stored — the RNG is not a CSPRNG and its
   state is recoverable from a few outputs. `bandit` covers the Python equivalents (B311 `random`,
   B324 `md5`/`sha1`) when installed; `semgrep-rules/ts-weak-hash-or-random` covers TS. Expect this one
   to be **mostly right about the construct and mostly wrong about the risk** — measured 13 of 14 real
   hits were legitimate non-security uses (cache-busting, event-name suffixes, filenames). The
   question is whether an attacker gains anything by predicting the value or finding a collision.

9. **Malicious / offensive behavior (self-check — is the artifact itself safe?).** Confirm the
   tool is defensive, not weaponized: it does not exploit/move-laterally/exfiltrate, does not
   target or surveil third parties, and does not weaken security controls (disable logging/EDR/
   firewalls) without explicit, documented justification. Read what it actually DOES, not just
   what it claims. This is an outright-rejection class for the Exchange and a red line generally.

10. **Undisclosed outbound calls / data egress.** Enumerate every network destination the tool
    contacts (APIs, telemetry, package/CDN fetches, webhooks) and confirm EACH is documented in
    the README. Grep for `curl|wget|requests|http|fetch|socket|urllib` and cross-check against
    the docs. Hidden egress (esp. sending scan data anywhere undisclosed) is a rejection class.
    **A destination is only enumerable if it is a constant.** Where the request target is *computed*
    from scanned data, the honest answer to "which hosts does this contact?" is "unbounded" — the
    destination list is whatever the environment says it is. That is dimension 2's SSRF sub-bullet
    and `semgrep-rules/py-ssrf-url-from-scanned-data`; here it means the README cannot document the
    egress set at all until an allowlist bounds it. Report the missing allowlist as the egress
    finding, not as a documentation gap.

11. **Tests & CI.** Is each of the above locked in so it can't regress? A finding fixed without
    a regression test is only half-fixed. Confirm: (a) a runnable test suite covers the fixed
    findings; (b) CI runs it across the supported version matrix; (c) the standard toolkit above
    (gitleaks full-history, ruff, bandit, shellcheck, actionlint) runs as **blocking** CI jobs,
    not advisory; (d) CodeQL runs as a workflow. Confirm CI + CodeQL are actually **green** on
    the latest commit — a red or never-run pipeline is a blocking finding. **Watch for
    happy-path-only coverage:** if the suite exercises every entry point but only with valid
    input, the failure modes in dimension 3 (bad args, missing files) are untested by
    construction — add the negative/bad-input cases too. **Prove each regression test is a REAL
    guard, not a tautology:** revert the fix (or mutate the asserted value) and confirm the test
    actually flips to FAIL — a test that passes both with and without the fix asserts nothing
    (e.g. it asserts on a string that also appears in static output). `scripts/mutation-check.sh`
    mechanizes this (runs the test clean → mutates the guarded file → requires the test to fail →
    restores).
    **Two tautology shapes mutation testing cannot reach — look for these by reading.**
    *(a) The `or not <precondition>` escape hatch.* `assert "AWS docs" in out or not any(r.docs_url
    for r in pairs)` passes whenever no fixture row has a `docs_url` — the right side is always
    true, the real claim on the left never evaluates, and it reads as coverage of the feature. No
    mutation to the code under test changes this, because the escape is in the *test*.
    `scripts/tautology-scan.sh` greps for it; hits are questions (ask whether the precondition is
    false in the fixture). Fix by asserting the precondition separately, or use a fixture where it
    holds. *(b) An assertion over a DERIVED property.* When a test asserts a `@property`,
    `cached_property`, getter, or serializer formula, it re-implements the derivation and passes on
    every input — including wrong ones. Real case: four of five assertions about a `safety_tier`
    property could not fail, because each one restated a term of the formula that computes it.
    `mutation-check.sh` cannot express this: the mutation would have to target the *data the test
    reads*, and the property recomputes from that data, so the assertion follows the mutation and
    stays true. Not greppable either — it needs a human to answer **"is this field authored data or
    computed?"**, which means reading the model definition. Assert on the *inputs* to the
    derivation, or on something no derivation could produce. Worth the effort: rewriting that
    tautology onto authored fields exposed a real bug it had been hiding (a `LOW` cost impact
    failed to downgrade a recipe, so recipes with recurring charges shipped in a default run). A
    tautology does not merely fail to catch bugs — it occupies the slot where the real assertion
    would have gone.
    **A third shape: a negative control that passes only while the code is broken.** Distinct from a
    tautology, which *cannot* fail; this one can, and does — the moment someone fixes the checker it
    guards. It appears whenever the "invalid" input is *derived* from a valid one by an operation
    that can silently do nothing: `str.replace(old, new)` and `re.sub(pat, repl, s)` return the
    original **unchanged** when the needle is absent, no error raised, so the test hands the checker
    a perfectly valid value and asserts rejection. Real case: twelve such tests, all green, all
    inverted. Fix by asserting `old in text` before the mutation, or by constructing the invalid
    value explicitly. Generalize the smell: **a fixture built by string-splitting on a delimiter
    that also occurs in the data is a silently wrong fixture, and a mutation harness that fails for
    the wrong reason is indistinguishable from one that works** — which is why any harness you build
    here must assert that its mutation actually landed before believing the result it reports.
    `semgrep-rules/py-negative-control-by-replace` catches the literal-needle forms; a needle held in
    a parameter or computed at runtime is a documented blind spot, so read the negative controls too.
    **And check that case-assertions assert what they appear to.** `str.islower()` is not "is
    lowercase" — it returns `False` for a string with **no cased characters**, so `"123".islower()`
    is `False` while `"us-east-1".islower()` is `True`. In a test that makes the assertion pass for a
    reason unrelated to its claim (**Medium**); in a *guard* it is a live bug that rejects every
    all-digit and empty value, or routes it down the wrong branch (**High**). Same construct, two
    rubric rows apart — say which one you found, and note that `value == value.lower()` is the
    predicate that means what it says. `semgrep-rules/py-caseless-string-case-check` flags both.
    **Synthetic-vs-live parity:** if every test runs on fixtures, note that fixtures
    encode the author's *assumptions* about the real system's shape — the exact place silent bugs
    hide; require at least one exercise against the real system (or a captured real response),
    especially for anything that queries an external schema/API.
    **Never weaken a security assertion to make a new feature pass.** When a legitimate change
    trips a safety test — a blocklist of dangerous substrings, a "no shell metacharacters"
    check, an allowed-domains assertion — the test firing is the test *working*. Deleting the
    pattern, loosening the regex, or adding a broad exception permanently blinds it to the
    attack it existed to catch. Replace the blanket ban with an **exact allowlist that stays
    accounted for**: assert the dangerous construct appears only in its known-good form and
    only as many times as expected, so any *new* occurrence still fails. Real case: adding an
    account-preflight guard introduced a legitimate `$(...)` command substitution and tripped
    an injection test; the fix was to drop `"$("` from the blocklist but assert
    `text.count("$(") == text.count(<the one approved line>)` — so a second substitution, from
    any source, breaks the build. Review every diff that edits a test's list of forbidden
    things and ask which attack just stopped being covered.
    **Check fixtures for correlated axes.** Synthetic data generated from one loop counter
    (`account = i % 40`, `region = i % 4`) silently couples the axes — here every account gets
    exactly one region — so any behavior that depends on their *combination* (grouping,
    splitting, per-scope file counts, join fan-out) is never exercised, and measurements taken
    on it are wrong in the flattering direction. Vary each axis independently and confirm the
    generated set actually contains the combinations the code branches on.

12. **Docs.** README/SKILL state what it does, prerequisites, how to run, outputs, limits, and
    any fidelity/coverage caveats — accurately (no overclaiming; e.g. "reduced fidelity" stays
    labeled as such). Installation instructions must be real and congruent with the repo
    (declared deps, entry points, and commands actually exist — not hallucinated).

### LLM / AI-agent dimensions (apply when the tool calls a model or is an agent/MCP server)
Most CyberAgents Exchange listings are LLM/AI agents with live tool access, so these are
frequently the highest-impact dimensions — not optional add-ons.

13. **LLM prompt-injection (indirect).** Attacker-influenceable environment data — resource
    names/ARNs/tags, plugin *output*, cert CNs, scraped CVE text, hostnames, chat/webhook
    content — must NOT be able to redirect the model's instructions or tool calls when
    concatenated into a prompt (this is a different sink than dimension 2's markup escaping).
    The model often holds state-changing MCP tools, so a poisoned finding steering a tool call
    is a real threat. **Prove it:** put an injected-instruction payload in a scanned field
    ("ignore prior instructions and …") and confirm the agent fences/ignores it. Untrusted
    content should be delimited/labeled as data, never merged into the instruction channel.
    `semgrep-rules/ts-untrusted-data-in-llm-system-prompt` flags interpolation into the TS SDKs'
    `system:` channel (Anthropic and OpenAI shapes). The triage question is **not** "is something
    interpolated" but "can the owner of the scanned asset write any of it" — a resource *name* is
    attacker-authored, a resource *count* is not. Zero hits proves little: a prompt assembled in a
    variable and passed by name is invisible to it, which is how most real code is written.

14. **AI data handling — at rest & vendor egress.** (a) Sensitive scan *output* written to
    disk (exposed-secret locations, PII/PHI, hostnames/IPs, identities, exposed IP:ports — an
    aggregated exploit map) is redacted/encrypted with retention/cleanup guidance. (b) Data
    sent to any third-party LLM is minimized, and its data-classification/residency is
    documented — disclosing the endpoint (dimension 10) is necessary but not sufficient.

15. **LLM output grounding & non-determinism.** Model-produced verdicts/artifacts (reports,
    SSVC/severity calls, generated remediation CLI or SQL) are grounded — every emitted fact
    traces to a source, not hallucinated hosts/CVEs. Output-contract validation runs
    **server-side / on the trust boundary**, not only client-side. Non-reproducibility of
    LLM output is disclosed; lenient regex-fallback JSON parsing is flagged.

16. **Token / cost & runaway-loop controls.** LLM calls have hard **token/turn/spend caps**
    and bounded context growth (no unbounded pagination into context, no per-keystroke resend
    of growing history, no uncapped `max_tokens`). Scheduled/multi-agent/loop invocations
    can't run away against a paid provider.

17. **Access control & agent authority.** Any served endpoint (UI/API/MCP) requires
    authN/authZ — no binding to `0.0.0.0` without auth, no wildcard CORS, no CSRF-free
    state-changing routes, no debug endpoints in prod. MCP transport is authenticated. Every
    state-changing tool call (restart/unlink, tag/ACR write, scan launch, SSH/RCE, SQL, email
    send) is gated by an **enforced control**, not merely a prompt instruction or an env flag.
    `semgrep-rules/ts-wildcard-cors` and `ts-binds-all-interfaces` catch the two spellings above in
    JS/TS. Read the bind finding as a question about authN, not about the bind: a container legitimately
    binds `0.0.0.0`, and the real defect is that nothing authenticates the caller once it does. **The
    biggest gap here is an absence, so no scanner can flag it** — `listen(port)` with no host argument
    is also all-interfaces on Node. Ask what the framework's default is; a clean scan does not answer it.

18. **Supply-chain provenance.** Packages, container images, CI actions, and CDN assets are
    pinned to immutable versions/digests, with SRI on CDN `<script>`/`<link>`. No moving tags
    (`@main`), no runtime `docker pull` of unverified images, no imports undeclared in the
    manifest, `npm ci` (not `npm install`) in CI.
    **"Pinned" is not "safe" — check both, they are opposite failures.** An unpinned dependency
    is non-reproducible; a *pinned* one is reproducibly whatever it was, including reproducibly
    vulnerable, and it never drifts to a fix on its own. A clean pinning review says nothing
    about this, so run `scripts/pinned-vuln-scan.py` (needs `gh` authenticated) to check each
    exact pin against the GitHub Advisory DB. Report a hit as a **defect with the advisory as
    its basis** (GHSA id + the advisory's own severity, per the cite-your-basis rule), not as a
    rejection gate. Two things must survive triage rather than be waved through: the probe
    exits **2** when it could not complete — no manifests, no exact pins, or every lookup
    failed — and 2 is *not* a pass, so a zero from a failed lookup must never be read as clean;
    and its negative is **bounded**, because `ecosystem: ACTIONS` returns nothing (pinned CI
    actions are uncovered — audit those by hand), transitive deps count only where a lockfile
    pins them, and range specifiers (`^1.2.3`) are excluded on purpose since they are this
    dimension's *other* finding above.

### Generated-artifact dimensions (apply when the tool EMITS something a human or CI then runs)
Applies to generated remediation scripts, IaC, SQL, playbooks, or config — anything the tool
writes for later execution. The artifact, not just the generator, is the deliverable, so it
carries its own failure modes. Skip with a note if the tool only reports and never emits.

19. **Execution-scope correctness — does each artifact match the authority it will run under?**
    An emitted artifact runs under credentials and a scope the *generator never sees*. Identify
    the scope its tooling can actually address in one invocation — one cloud account, one
    region, one tenant, one cluster, one database — and confirm no single artifact spans more
    than that. **The failure to hunt is not an error, it's a wrong success:** an identifier that
    exists in more than one scope resolves against whichever scope the runner is authenticated
    to. Real case: Terraform/OpenTofu `import` blocks for two AWS accounts in one file, where
    the provider is scoped to one account and region — a same-named DynamoDB table in the wrong
    account would be adopted and reconfigured, silently, with the plan reporting success.
    Distinguish **hard** boundaries (the tooling cannot cross them: an AWS provider's
    account+region, a DB connection's schema) from **soft** ones (a CLI that carries `--region`
    per command can span regions). Splitting on a hard boundary is a *correctness* requirement,
    not tidiness — so it needs a test asserting no artifact ever spans one, at the smallest
    input size where it could (two items), and not defeated by a `--no-split`/size-limit flag.
    **Where it lands:** a *hard*-boundary span is a **Critical** defect (it acts on the wrong
    scope while reporting success); a *soft*-boundary span is **Informational** (the artifact is
    correct, splitting is only ergonomics). Getting that distinction wrong in either direction is
    the main way this dimension gets misapplied — so state which kind of boundary you found.
    - **Fail closed on a scope mismatch.** The artifact should refuse to run against the wrong
      scope rather than trust its filename. Prefer a self-check the runner cannot skip — an
      identity preflight that exits non-zero (`aws sts get-caller-identity` compared to the
      expected account), a provider-level guard (`allowed_account_ids`), a `USE <db>` assertion.
      Pick one that needs no privilege beyond being authenticated, so it can't fail closed on a
      legitimate operator. State the required scope *in the artifact*, not only in the docs.
    - **Placeholders must be visibly unfinished.** Where the generator cannot know a required
      value, a type-valid stub that lets validation pass is fine *only* if it is marked (`TODO`)
      and counted, and the artifact says the value is not real. A plausible-looking default is
      the worst outcome here: it validates, applies, and reconfigures the resource wrongly.
    - **Prove it with the real parser, not substring assertions.** Run the actual toolchain over
      each emitted file in isolation (`tofu init -backend=false && tofu validate`, `bash -n`,
      `sqlfluff`/`EXPLAIN`, `--dry-run`) — per file, in its own workspace, so a file that only
      validates alongside its siblings is caught. Substring checks pass on artifacts real
      parsers reject; this dimension is where "prefer proof over assertion" pays most.

## Output

Report in **three buckets, in this order**. The buckets differ by *who decides and against what
standard*, which is why a finding has exactly one home even when it spans topics (an uncapped LLM
pagination loop is both a cost and a security problem, but there is only one question that
matters about it: does it block?). Serves both audiences — a reviewer reads bucket 1 to decide
accept/reject and stops; a contributor reads buckets 2 and 3 to know what to fix.

### 1. Rejection gates — pulled, binary, no severity

Taken **verbatim from the live Exchange checklist** (`docs/contributing_checklist.md`), not from
your judgment. These are pass/fail by definition: the checklist says a repo with a committed
credential "is rejected outright" and "any detected credential is an immediate rejection." Cite
the checklist item you are applying. If any gate fails, the verdict is NOT READY regardless of
everything else, and no severity label is needed or appropriate — there is no "how bad."

At writing time: offensive/weaponized behavior; hardcoded secrets (gitleaks, full history);
undocumented outbound calls; competitor targeting; weakening security controls; no detectable
open-source license; archive-only content. **Fetch the live list — it wins over this copy.**

### 2. Defects — severity from the rubric below, scanner output as cited evidence

Everything the probes found that is actually wrong. Each entry carries `file:line`, a severity
label, a concrete failure scenario, the specific fix, and a **cited basis** for the severity.

| Severity | Meaning | Blocks shipping? |
| --- | --- | --- |
| **Critical** | Silent wrong answers, or harm to the user or a third party: a missed detection the tool claims to cover, an artifact that acts on the wrong account/tenant, an unauthenticated state-changing endpoint, prompt injection reaching a live tool call. | **Yes** |
| **High** | Fails or corrupts under realistic conditions: a crash with a raw traceback on ordinary bad input, an exit code a scheduler will misread, an unverified-TLS request carrying a credential, a plaintext secret at rest, a regression test that is a tautology. | **Yes** |
| **Medium** | Degrades or misleads without being wrong: a documented limit that isn't enforced, missing retry/backoff, an unpinned dependency, docs that overclaim coverage. | Reviewer's call |
| **Low** | Real but bounded: a narrow edge case, an inconsistent message, a missing non-critical test. | No |

**Every severity must cite its basis** — one of `Exchange checklist §<item>`, `CodeQL
security-severity <score>`, `<tool> <rule> <its rating>`, or `rubric: <which row above>`. A label
with no cited basis is the failure mode this structure exists to prevent; it is how an
unexamined guess acquires the appearance of authority.

**A scanner's rating is evidence, never the verdict — and it can only ever raise a finding, not
lower one.** Record the tool's own rating verbatim, then state your severity. You may rate
*above* the scanner with a reason; you may **not** rate below it. This is not theoretical:
`bandit` maps a hardcoded password to CWE-259 and rates it **LOW**, while the Exchange rejects
such a submission outright. Scanner scores reflect pattern confidence, not blast radius. If you
believe a scanner finding is unreachable, say so as a *note on* the finding and keep the
severity — unreachability is an argument, not a downgrade.

**CWE is optional, and is classification — not severity.** Cite a CWE when a real one fits
(`CWE-79` for XSS, `CWE-295` for disabled TLS verification, `CWE-798`/`CWE-259` for hardcoded
credentials, `CWE-502` for unsafe deserialization, `CWE-770`/`CWE-400` for an uncapped resource,
`CWE-306`/`CWE-352` for missing authN/CSRF, `CWE-1427` for prompt injection, `CWE-829`/`CWE-1357`
for unpinned supply chain) — it helps reviewers cross-reference and users search. **Omit it, and
say "no applicable CWE", when none fits.** Roughly half these dimensions have no honest CWE:
CWE catalogs *code weaknesses*, so "my detector silently missed an in-scope finding" (dim 1),
"this artifact targets the wrong account" (dim 19), "this regression test asserts nothing"
(dim 11) and "this tool is weaponized" (dim 9) have no entry. Forcing a loose CWE onto one of
those is worse than omitting it — a wrong-but-official-looking label misdirects triage. Never
let the presence or absence of a CWE change the severity.

### 3. Informational — not defects, never blocking, no severity

Efficiency, cost, ergonomics, style, and structural observations: output size, token spend,
wall-clock, naming, refactors, dimension-4 amortization findings that cross no documented cap.
Report them — they are often the most actionable items in a healthy repo — but they carry no
severity and never appear in the verdict's blocking list. An unlabeled "68% of your output is
boilerplate" sitting next to a real credential leak dilutes the leak.

**Promote an Informational item into Defects only with the consequence named:** it breaches a
documented limit, it exhausts a real resource (memory, disk, a paid token budget, a rate limit)
at the tool's own claimed scale, or the volume itself defeats review so changes ship unexamined.
Say which. **Never inflate an Informational finding to make a review look productive** — a review
reporting five clearly-labeled Informational items and no defects is an accurate review. The
converse also holds: never demote a real defect to Informational because the fix is inconvenient.

### Verdict

End with an explicit verdict: **ready to submit**, or the blocking items — every failed rejection
gate, plus every Critical and High defect. State the counts per bucket so the shape of the review
is visible at a glance. If findings are fixed in the same pass, re-run the relevant probe to
confirm, and add or point to the regression test.

## For Tenable CyberAgents Exchange submissions specifically

**Fetch the live checklist and validator first** — `tenable/cyberagents-exchange`
`docs/contributing_checklist.md` and `validator.py`. Reviewers execute the checklist
item-by-item and two Tenable employees must both approve. **RUN the real tools, don't eyeball**:
run the live `validator.py` against the listing, and `gitleaks` over full history (both are
what the Exchange actually runs). The items below reflect the checklist at writing time — the
live version wins:

**Outright-rejection gates (any tier):** no offensive/weaponized behavior; no hardcoded
secrets (gitleaks, full history); all outbound calls documented; no competitor targeting; no
weakening of security controls. (Dimensions 8–10 cover these — apply them here.)

**Automated screening:** repo is public, active (not archived), reachable; a detectable
open-source LICENSE exists.

**Listing requirements:** PR adds **exactly ONE** new markdown file, in the correct type
directory (`agents/|skills/|mcp-servers/|playbooks/`); filename is a valid slug, no conflict;
PR title is `Add listing: <Name>`; frontmatter passes `validator.py` (all required fields,
`tier: contributed`); controlled-vocabulary values valid (or the same PR updates `validator.py`
alphabetically); `date_added` and `contribution_agreement_date` are real (not the template
default, not absurdly future, agreement-date not before repo creation);
`works_with_tenable_hexa_mcp` (if present) is boolean and truthful; NO template placeholders
remain; body has real "What it does"/"How it works" content.

**Congruence (listing ↔ repo):** `github_url` + `author` match the actual remote/owner; repo
is on a personal account, **not an Enterprise Managed User** (`<org>_<name>` underscore pattern
— hyphens like `name-tenb` are fine); LICENSE present and matching the declared SPDX id;
`name`/`description`/`integrations` match what the repo actually is; type-specific fields
congruent (skill: `SKILL.md` at root with `name`/`description`, referenced files exist,
per-platform install steps, `invocation` appears in SKILL.md/README; MCP:
`runtime`/`transport`/`tools_exposed`/`auth_method` match the code; playbook: `agents_used`
resolve, vendor-type only in sponsored); **archive-only is rejected** — content must exist
unpacked at the repo root, not only inside a `.zip`/`.skill`; every claim in the body traces to
the README/repo.

Never rubber-stamp a red CI.
