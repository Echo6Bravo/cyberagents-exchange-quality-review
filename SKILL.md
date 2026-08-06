---
name: cyberagents-exchange-quality-review
description: >-
  Adversarial pre-submission quality gate for cybersecurity agents/skills/MCP servers,
  especially those bound for the Tenable CyberAgents Exchange. Systematically hunts the
  failure classes that hurt a customer — detection false-negatives, injection/XSS, messy-data
  robustness, scale limits, operational behavior, version portability, schema drift, leaked
  secrets (full git history), malicious/offensive behavior, undisclosed outbound calls,
  LLM/AI-specific risks, and execution-scope correctness in generated artifacts — and reports
  findings ranked by severity BEFORE any public/Exchange push. Runs a standard toolkit (gitleaks, ruff, bandit, shellcheck, actionlint, CodeQL) and
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
- **Python lint/SAST:** `ruff check .` and `bandit -r .`. Leave ruff's `S` (flake8-bandit) rules
  **off** — they are a port of bandit's checks (`S501` ≡ `B501`), so enabling them here would
  report every Python security finding twice and inflate the count. `bandit` owns that lane.
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

2. **Input safety — injection/XSS.** Every value sourced from the scanned environment (names,
   IDs, components, free text) that reaches HTML/SVG/CSV/shell/SQL must be escaped/parameterized
   for its sink. Prove it: inject `<script>`, attribute-breakout, and formula-injection
   payloads into every field and verify (DOM-level / parser-level) that nothing executes.
   CodeQL's taint queries are the automated backstop — but the payload-injection probe is the
   primary proof; don't rely on the scanner alone.

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

9. **Malicious / offensive behavior (self-check — is the artifact itself safe?).** Confirm the
   tool is defensive, not weaponized: it does not exploit/move-laterally/exfiltrate, does not
   target or surveil third parties, and does not weaken security controls (disable logging/EDR/
   firewalls) without explicit, documented justification. Read what it actually DOES, not just
   what it claims. This is an outright-rejection class for the Exchange and a red line generally.

10. **Undisclosed outbound calls / data egress.** Enumerate every network destination the tool
    contacts (APIs, telemetry, package/CDN fetches, webhooks) and confirm EACH is documented in
    the README. Grep for `curl|wget|requests|http|fetch|socket|urllib` and cross-check against
    the docs. Hidden egress (esp. sending scan data anywhere undisclosed) is a rejection class.

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

18. **Supply-chain provenance.** Packages, container images, CI actions, and CDN assets are
    pinned to immutable versions/digests, with SRI on CDN `<script>`/`<link>`. No moving tags
    (`@main`), no runtime `docker pull` of unverified images, no imports undeclared in the
    manifest, `npm ci` (not `npm install`) in CI.

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
