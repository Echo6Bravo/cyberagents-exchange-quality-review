---
name: cyberagents-exchange-quality-review
description: >-
  Adversarial pre-submission quality gate for cybersecurity agents/skills/MCP servers,
  especially those bound for the Tenable CyberAgents Exchange. Systematically hunts the
  failure classes that hurt a customer — detection false-negatives, injection/XSS, messy-data
  robustness, scale limits, operational behavior, version portability, schema drift, leaked
  secrets (full git history), malicious/offensive behavior, undisclosed outbound calls, and
  LLM/AI-specific risks — and reports findings ranked by severity BEFORE any public/Exchange
  push. Runs a standard toolkit (gitleaks, ruff, bandit, shellcheck, actionlint, CodeQL) and
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
for t in gitleaks ruff bandit shellcheck actionlint; do
  command -v "$t" >/dev/null 2>&1 && echo "present: $t" || echo "MISSING: $t"
done
```
Then state, up front, something like: *"Running with gitleaks+ruff+bandit present; shellcheck
and actionlint MISSING → the shell and workflow dimensions run in degraded (manual) mode."*
Offer to install missing tools (`bash setup.sh`, or `brew install …` / `pipx install bandit`)
— but **only with the user's approval**; never assume you may install software. If a tool
stays missing, run that dimension's documented fallback and **label the finding "degraded —
<tool> not available"** so the gap is visible. CodeQL is a GitHub-Actions workflow on the
target repo, not a local install (see the toolkit note).

**Shipped helper scripts — run them WHEN THEIR PRECONDITIONS HOLD; skip-with-a-note otherwise.**
These two are part of the review by default, but only when they apply — forcing a tool that
doesn't fit is exactly the overreach this skill warns others against (dim 3: degrade gracefully).
Decide per target, and state the decision out loud like any other coverage call:
- **`scripts/empty-relationship-scan.sh <target>` (dimension 1).** Run it **if** the target has
  source in a supported language (`.py/.js/.ts/.jsx/.tsx/.go/.rb/.sh/.java`). Triage every hit as
  a *question* (read the code; is a missing/empty value excluded or silently passed?), not a
  confirmed bug. If the language isn't covered or it flags nothing, **say so and note it is not
  proof of safety** — still write the real empty-input test. Cheap (grep-only); default to running
  it whenever any supported source exists.
- **`scripts/mutation-check.sh` (dimension 11).** For each regression test backing a fixed finding,
  run it to prove the test FAILS on revert — **only if all preconditions hold:** (a) a runnable
  test command exists; (b) it is fast and **side-effect-free** (no live tenant/API token, no
  network, no paid calls, no state mutation); (c) the suite is green to begin with; (d) the target
  working tree is clean (it edits a file in place and restores via trap, so a dirty tree adds
  risk). If any precondition fails — slow/networked/absent tests, dirty tree, nothing fixed to
  guard — **do NOT force it**: note that the guard was verified by reasoning, not mechanically, and
  say which precondition blocked it. Never fabricate a test command just to run it.

Treat both like the scanners above: their absence or non-applicability is a *labeled coverage gap*,
never a silent skip and never a reason to overstate what was checked.

## Standard toolkit — RUN these, don't eyeball
Run whatever of these the language/stack supports; treat findings as input to the relevant
dimension, not a substitute for it. Install only with the user's approval (`bash setup.sh`).
- **Secrets:** `gitleaks git --no-banner --redact .` over **full history** (fetch-depth 0 in CI).
- **Python lint/SAST:** `ruff check .` and `bandit -r . --skip B101` (B101=asserts are usually
  intentional dev-time checks — skip with a documented reason, don't rewrite working asserts).
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
    restores). **Synthetic-vs-live parity:** if every test runs on fixtures, note that fixtures
    encode the author's *assumptions* about the real system's shape — the exact place silent bugs
    hide; require at least one exercise against the real system (or a captured real response),
    especially for anything that queries an external schema/API.

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

## Output

Report as: dimension → findings (most severe first) with `file:line`, a concrete failure
scenario, and the specific fix. End with an explicit **verdict**: ready to submit, or the
blocking items. If findings are fixed in the same pass, re-run the relevant probe to confirm,
and add/point to the regression test.

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
