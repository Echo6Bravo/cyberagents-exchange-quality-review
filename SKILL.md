---
name: quality-review
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

## Standard toolkit — RUN these, don't eyeball
Run whatever of these the language/stack supports; treat findings as input to the relevant
dimension, not a substitute for it. Install if missing.
- **Secrets:** `gitleaks git --no-banner --redact .` over **full history** (fetch-depth 0 in CI).
- **Python lint/SAST:** `ruff check .` and `bandit -r . --skip B101` (B101=asserts are usually
  intentional dev-time checks — skip with a documented reason, don't rewrite working asserts).
- **Shell:** `shellcheck -S warning` on every `*.sh`.
- **GitHub Actions:** `actionlint` on every workflow (catches invalid inputs before a failed run).
- **Deep SAST:** **CodeQL** — best run as a GitHub Actions workflow (`github/codeql-action`,
  `security-and-quality` suite, free for public repos, results in the Security tab). The CLI
  often can't fetch query packs behind a corporate TLS proxy, so prefer the Action. Triage
  alerts by security-severity; low-severity style notes are fixed or justified, not ignored.
Every one of these should also be a **CI gate** so it can't regress (see dimension 11).

## Dimensions (in priority order — customer-impact first)

1. **Detection correctness — false NEGATIVES (highest priority for a security tool).**
   Does any real, in-scope finding get silently dropped? Check allow-lists/keep-lists for
   coverage gaps; confirm the tool SURFACES unknowns for review rather than discarding them.
   Probe with inputs the maps don't explicitly know about.

2. **Input safety — injection/XSS.** Every value sourced from the scanned environment (names,
   IDs, components, free text) that reaches HTML/SVG/CSV/shell/SQL must be escaped/parameterized
   for its sink. Prove it: inject `<script>`, attribute-breakout, and formula-injection
   payloads into every field and verify (DOM-level / parser-level) that nothing executes.
   CodeQL's taint queries are the automated backstop — but the payload-injection probe is the
   primary proof; don't rely on the scanner alone.

3. **Robustness on messy data.** Null/missing fields, wrong types, duplicates, empty result
   sets, truncated/interrupted inputs, malformed pages. Each must fail cleanly with an
   actionable message (never a raw stack trace) or degrade gracefully. Verify the exit-code
   contract.

4. **Scale.** Estimate volume at 10–50x the test environment (pull size, memory, output size,
   algorithmic complexity). Confirm caps/streaming/chunking exist and that nothing is silently
   truncated. Extrapolate output size; open the result.

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
    the latest commit — a red or never-run pipeline is a blocking finding.

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
