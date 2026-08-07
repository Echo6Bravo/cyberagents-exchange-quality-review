# cyberagents-exchange-quality-review — a pre-submission quality gate for CyberAgents Exchange work

A Claude Code **skill** that runs an adversarial, proof-over-assertion quality and security
review of a cybersecurity agent / skill / MCP server **before** you push it publicly or submit
it to the [Tenable CyberAgents Exchange](https://exchange.tenable.com). It turns "did I miss
anything?" from a gut check into a repeatable checklist that finds the failure classes that
actually hurt a customer — and mirrors the Exchange's own reviewer checklist so you clear
review with fewer round-trips.

> This is a community contribution authored by a Tenable employee (hence the © Tenable, Inc. on
> the MIT license), but it is **not** an official, supported Tenable product, and passing it is
> **not** a guarantee of Exchange acceptance — the live Exchange checklist and `validator.py`
> are always authoritative. The skill fetches and defers to them at review time.

## What it does

Invoke it (e.g. "run a quality review", or `/cyberagents-exchange-quality-review`) and it works **19 dimensions**,
ranked by customer impact, reporting findings in three buckets (rejection gates → defects →
informational) with a concrete repro and fix, then an explicit **verdict** (ready, or the
blocking items).

**Core (1–12):** detection false-negatives; injection/XSS; messy-data robustness; scale;
operational (exit codes / retry / determinism); version portability & TLS; schema/contract
drift; secrets (full git history + credential-at-rest); malicious/offensive self-check;
undisclosed egress; tests & CI; docs.

**LLM / AI-agent (13–18)** — for tools that call a model or act as an agent/MCP server:
prompt-injection (indirect); AI data handling (at-rest & vendor egress); LLM output grounding
& non-determinism; token/cost & runaway-loop controls; access control & agent authority
(endpoint authN/authZ, MCP auth, tool gating); supply-chain provenance.

**Generated artifacts (19)** — for tools that *emit* something a human or CI later runs
(remediation scripts, IaC, SQL, playbooks, config): execution-scope correctness — no single
artifact spans more scope than its tooling can address in one invocation, it fails closed on a
scope mismatch rather than trusting its filename, unfinished values are visibly marked, and the
real parser validates each file in isolation.

Plus a **Tenable Exchange submission** section that mirrors the live contributing checklist
(automated screening, listing requirements, listing↔repo congruence, outright-rejection gates).

## How findings are reported

Output lands in **three buckets**, which differ by *who decides and against what standard* — so a
reviewer reads bucket 1 to decide accept/reject and can stop there, while a contributor reads
buckets 2 and 3 to know what to fix.

1. **Rejection gates** — taken verbatim from the live Exchange checklist (committed secrets,
   weaponized behavior, no license, undisclosed egress, …). Binary, no severity: the checklist
   says a detected credential is "an immediate rejection," so there is no *how bad*. Any failed
   gate makes the verdict NOT READY on its own.
2. **Defects** — real problems, labeled **Critical / High / Medium / Low**, scored on consequence
   rather than effort to fix. Every severity must **cite its basis** (an Exchange checklist item,
   a CodeQL `security-severity` score, a scanner rule and its rating, or the rubric row) — an
   unsourced label is the failure mode this structure exists to prevent. A scanner's rating is
   evidence that can **raise but never lower** a finding: `bandit` rates a hardcoded password
   **LOW**, while the Exchange rejects that submission outright. A **CWE is optional** and is
   *classification, not severity* — cite one where a real one fits, and say "no applicable CWE"
   where none does, because a wrong-but-official-looking label misdirects triage.
3. **Informational** — efficiency, cost, ergonomics, style. No severity, never blocking, so a
   "70% of your output is boilerplate" note can't read like a credential leak. Promoting one into
   Defects requires naming the consequence (a breached documented limit, a real resource exhausted
   at claimed scale, or volume that defeats review).

CI enforces that the three buckets exist in order, that the severity taxonomy and the
cite-your-basis / raise-never-lower / CWE-is-optional rules stay stated, and that the example
review keeps severity labels inside the Defects bucket only.

For each dimension it **actually runs a probe** (adversarial input, a container, a scanner)
rather than reasoning about it, and treats each tool as a CI gate that must stay green.

See [`examples/sample-review.md`](examples/sample-review.md) for what a run's output looks
like.

## The toolkit — who covers what

Each tool owns a lane. The point is **no overlap**: two tools reporting the same defect twice
inflates a finding count and makes a review look deeper than it is.

| Tool | Lane | Notes |
|---|---|---|
| **gitleaks** | Secrets, **full git history** | A secret in an old commit is still leaked; `fetch-depth: 0` in CI |
| **ruff** | Python lint / correctness | Fast; the `S` (flake8-bandit) rules are **deliberately not enabled** — see below |
| **bandit** | Python security (SAST) | Owns Python security outright: `verify=False` → B501, `md5` → B324, `pickle.loads` → B301, unsafe `yaml.load` → B506, `random` for a token → B311 (all verified by running it, not read off its docs). **Optional**, so credit that coverage conditionally |
| **semgrep** | **Everything Python tools can't reach — JS/TS above all** | This skill's **own rules only**; see below |
| **shellcheck** | Shell scripts | `-S warning` |
| **actionlint** | GitHub Actions workflows | Catches invalid inputs before a failed run |
| **CodeQL** | Deep dataflow/taint | Run as a **GitHub Action**, not locally — the CLI usually can't fetch query packs behind a corporate TLS proxy |

**Why `ruff`'s `S` rules stay off:** they are a port of bandit's checks (`S501` ≡ `B501`). Enabling
them alongside `bandit` would report every Python security finding twice. `bandit` keeps that lane.

### How semgrep fits — and the one thing to know before installing it

semgrep exists here to cover **JS/TS**, which `ruff` and `bandit` cannot see at all. That gap
matters: a large share of Exchange listings are TypeScript MCP servers, so without it those repos
got `gitleaks` plus a human read and nothing else.

**Installing semgrep is not the same as gaining coverage.** It ships **no bundled security rules** —
out of the box it is an engine with nothing to run. So this skill reports it in **three** states, and
`bash setup.sh --check` tells you which one you're in:

| State | What the review can claim |
|---|---|
| `[MISSING] semgrep` | Nothing. JS/TS dimensions run in degraded (manual) mode. |
| `[present]` → *engine present but NO rules loadable* | **Still nothing.** Counts as MISSING for coverage. |
| `[present]` → *custom rules only: `scripts/semgrep-rules`* | Whatever those rules cover, and no more. |

Two deliberate constraints:

- **The hosted registry (`--config p/…`) is not used.** Rules are authored in-repo so their severity
  mapping matches this skill's rubric, and so every rule maps to a numbered dimension. It is also
  frequently unreachable behind a corporate TLS proxy — and the config fetch has **no bounded
  timeout**, so a naive attempt can hang for minutes rather than failing fast.
- **semgrep never duplicates bandit.** If bandit already catches a Python shape, there is
  deliberately no semgrep rule for it. A duplicate finding is a bug in the rule set. This is why the
  TLS, crypto, and deserialization rules are **TypeScript-only** — `bandit` owns B501, B311/B324, and
  B301/B506 for Python. It is also why the skill states that coverage *conditionally*: `bandit` is
  optional, so when it is absent Python is as uncovered as TypeScript was.

**What the rules are measured against, stated as a bound rather than implied.** Every rule ships with
its own fixture (`semgrep test` requires the reported lines to equal the annotated lines exactly, so
unannotated near-misses are enforced true negatives), a documented false-positive list, and a
documented blind-spot list. Beyond the fixtures, the set was run against **1138 real JS/TS files
(~392k lines)**: 30 findings, all genuine instances of the flagged construct, in 15 files — 14 of
which were vendored third-party libraries. Two honest caveats travel with that number, and the skill
tells the assistant to repeat them rather than report a bare zero:

- **Three rules found nothing because that corpus contains no instances of what they look for.** A
  laptop's JS is mostly browser and CLI code, with no server TLS or bind configuration in it. That is
  a true negative with no discriminating power, not a precision result.
- **A second measurement, on the population these rules are actually for.** The TS rules were re-run
  against **1074 TypeScript files from six real MCP servers** (official `servers` + `typescript-sdk`,
  context7, Figma-Context-MCP, mcp-server-cloudflare, playwright-mcp; 13 further files failed to parse
  and are excluded from that denominator). 25 findings, every one triaged by reading the source.
  `ts-wildcard-cors` was the highest-firing at 13 (8 in production paths) and every hit was genuine —
  wildcard CORS is near house style on MCP servers, so the rule's job there is classifying *intent*.
- **The most instructive hit was a false positive, and it is documented as one.** `ts-weak-hash-or-random`
  flagged `Math.random()` feeding the `jti` claim of a private-key-JWT client assertion in the official
  SDK. It looks like a High: auth file, named claim, citable RFC. It is not a defect — RFC 7519 §4.1.7
  asks `jti` for *collision resistance*, not unpredictability, and every replay path is gated by the
  assertion's **signature**, not by guessing `jti`. Measured 0 collisions in 2,000,000 values. The rule
  header now carries the triage rule this produced: ask **which property** the consumer needs — uniqueness
  or unpredictability — and read the spec rather than inferring it from the field's name.
- **The three newest TS rules were measured *before* they were written, and one of them is a triage
  queue rather than a defect list.** Authoring and measuring is one task here, because shipping a rule
  the corpus has never seen recreates exactly the `ts-binds-all-interfaces` blind spot described below.
  `ts-failopen-on-exception` matches only `return true` and `return []` in a `catch` because the corpus
  showed 33 permissive catch returns distributed **null: 18, undefined: 11, []: 4, true: 0** — matching
  `null`/`undefined` would have made the rule ~88% noise, so the exclusion is a measurement, not taste.
  `ts-ssrf-url-from-scanned-data` measured **182 findings**, reduced to 60 by excluding test files and
  provably-safe URL shapes; it stays noisy because 154 of the 182 pass a bare variable that no
  syntactic rule can resolve, so its output is a queue of one question — *where does the host come
  from?* — not a finding list. `ts-path-write-without-containment` measured 43 (11 outside tests), and
  its most instructive hit is a **false positive** whose containment lives in the caller.
- **A fourth rule was deliberately not written, because the bug does not port.** A TypeScript version of
  `py-caseless-string-case-check` was scoped and dropped: in Python `"123".islower()` and
  `"123".isupper()` are *both* False, which is what makes the check wrong, whereas in JS
  `s === s.toLowerCase()` is **true** for `"123"`. The semantics are inverted, not transplanted, so a
  port would have been a rule for a bug that does not exist.
- **That run also found a defect in one of these rules, which is the point of measuring.**
  `ts-binds-all-interfaces` reported zero against a corpus holding 102 `.listen(` calls, because modern
  MCP servers bind via a framework factory rather than `.listen()`. It was missing 8 real sites. A zero
  is only evidence after you have checked that the construct is present — otherwise it is a blind spot
  wearing a passing grade.
- **Vendored code dominates the hits.** All 16 `eval`/`new Function` findings were in prototype.js,
  YUI, socket.io, and ace — correctly flagged, and all the same already-known fact about code the
  submitter didn't write. Scope scans to first-party source, or a vendored bundle will make a review
  look deeper than it is.

Invocation (the two flags are not optional — without them a blocked update check adds ~90s):

```bash
semgrep scan --config scripts/semgrep-rules --metrics=off --disable-version-check <target>
```

### Probes this skill ships itself

For bug classes no off-the-shelf scanner covers, in `scripts/`:

| Script | Finds | Dim |
|---|---|---|
| `mutation-check.sh` | A regression test that passes with **and without** the fix — reverts the fix and requires the test to fail | 11 |
| `empty-relationship-scan.sh` | `LOOKUP.get(k) or set()` fallthroughs, where a *missing* relationship silently satisfies a gate | 1 |
| `tautology-scan.sh` | `assert … or not <precondition>` escape hatches — assertions that pass without ever evaluating their real claim | 11 |
| `field-coverage-scan.sh` | Hostile-value payloads applied to **one field** — diffs declared string fields against the fields any hostile test names | 2 |
| `pinned-vuln-scan.py` | Dependencies that are **pinned and vulnerable** — a clean pinning review says nothing about this, since a pin reproduces whatever it was and never drifts to a fix. Checks each exact pin against the GitHub Advisory DB via `gh` | 18 |
| `semgrep-rules/` | **15 authored rules** for shapes `ruff`/`bandit` cannot reach — ten of them JS/TS, which nothing else in the toolkit can parse: credentials in `localStorage`; `rejectUnauthorized: false`; wildcard CORS and `listen(…, "0.0.0.0")`; scanned data interpolated into an LLM `system:` prompt; `eval`/`new Function`/unsafe `yaml` schema; `md5`/`Math.random()` for security values; a `catch` that returns a permissive value; an SSRF URL built from scanned data; a file write with no containment guard. Plus five Python rules: two test-quality shapes, path containment, an SSRF URL built from scanned data, and an exception handler that fails **open**. | 2, 3, 6, 8, 11, 13, 17 |

Every scanner except `mutation-check.sh` is a **heuristic**: each hit is a question to answer by
reading the code, never a confirmed defect, and **zero hits is never proof**. Each ships with tests,
documented false positives, and documented blind spots. `tautology-scan.sh` covers the shape
`mutation-check.sh` structurally cannot: when the escape hatch is in the *test*, no mutation of the
code under test changes the result. `field-coverage-scan.sh` exits **2**, not 0, when it finds no
models or no hostile tests — there is nothing to compare, and reporting that as a pass would be the
silent zero these probes exist to catch. `pinned-vuln-scan.py` uses the same exit-2 discipline for
"could not complete" (no manifests, no exact pins, or every lookup failed), and its negative is
explicitly bounded: `ecosystem: ACTIONS` returns nothing, so **pinned CI actions are not covered**.

`pinned-vuln-scan.py` needs no install beyond `gh`, which the skill already requires, and it
hand-rolls its version comparator rather than importing `packaging` — measured, that module is
importable on only one of the four interpreters on a typical machine, and a probe that dies on
`ImportError` reports nothing. The comparator was differentially tested against `packaging` over
**144,199 ordered version pairs (100% agreement)** and against the semver.org §11 precedence chain,
its range evaluator checked against **736 real advisory ranges** from 43 packages, and its own
test suite mutation-tested to **28/28 mutants caught** — including three rounds where a survivor
exposed a real gap, one of them a bug the suite provably could not detect. Against live API data,
**38 findings across 7 packages were independently re-derived with 0 precision violations**. Running
it on real manifests also found a false negative no fixture had: hash-pinned `pip-compile` output
(`attrs==25.3.0 \` followed by `--hash` lines) parsed as *no pins at all*, so the most rigorously
pinned repos were exactly the ones reported as having nothing to check.

## Install

Clone into your Claude Code skills directory:

```bash
# global (all projects)
git clone https://github.com/Echo6Bravo/cyberagents-exchange-quality-review.git \
  ~/.claude/skills/cyberagents-exchange-quality-review

# or per-project
git clone https://github.com/Echo6Bravo/cyberagents-exchange-quality-review.git \
  .claude/skills/cyberagents-exchange-quality-review
```

Then invoke it in Claude Code: **"run a quality review on this repo"** or `/cyberagents-exchange-quality-review`.
Skills follow the [Agent Skills](https://docs.anthropic.com/en/docs/claude-code/skills)
standard, so it also works in other assistants that support it.

## Optional tooling (the skill uses these if present)

The scanners are **optional** — the skill degrades gracefully and, on every run, tells you the
coverage level up front (which tools ran, which dimensions are degraded). For the deepest
review, install the toolkit in one step:

```bash
bash setup.sh          # installs gitleaks, ruff, bandit, shellcheck, actionlint, semgrep
bash setup.sh --check  # just report what's present/missing, install nothing
```

Or install manually: `brew install gitleaks ruff shellcheck actionlint semgrep` and
`pipx install bandit`.

**semgrep is reported as three states, not two.** It ships no bundled security rules, so the binary
being present says nothing about coverage. This skill drives it with **only its own rules** in
`scripts/semgrep-rules` — the hosted registry (`--config p/…`) is not used, and is often
unreachable behind a corporate TLS proxy anyway. `setup.sh --check` tells you which state you're
in: missing, present-but-no-rules (**contributes no coverage**), or present with the skill's rules.

**CodeQL is deliberately not installed locally.** It runs best as a GitHub Actions workflow
(`github/codeql-action`) on the repository you're reviewing — free for public repos, nothing
to install, results in the repo's Security tab. The skill *recommends adding that workflow*
and confirms it's green; it does not (and cannot) run CodeQL on your machine or someone else's
repo for them.

> **What this skill is:** instructions that guide an AI assistant — not a standalone program.
> It installs nothing without your approval and runs commands in *your* environment. Its
> thoroughness depends on the assistant executing the probes and on which tools are present
> (hence the up-front coverage report). Treat its verdict as a strong pre-check, not a
> certification.

## Prerequisites

- **Claude Code** (or another Agent-Skills-compatible assistant).
- **`gh`** (GitHub CLI) for the Exchange-submission checks (reading the live checklist/validator).
- The scanners above are optional — the skill degrades gracefully and notes what it couldn't run.

## CI

This repo runs the same gates it recommends (dimensions 8, 11, 18), in four jobs: **gitleaks**
full-history secret scan, **actionlint** on its own workflow, a **SKILL.md structure check** (valid
`name`/`description` frontmatter, substantive body, all 19 dimensions present, the three output
buckets in order, the severity rules stated, no leftover placeholders) plus a check that the
example review obeys the bucket structure, and **shellcheck + ruff + the helper-script suite** (123
tests, including the six gates on the semgrep rules and `pinned-vuln-scan.py`'s offline self-test). Each check ships with a negative control — it
was verified to *fail* when the thing it guards is removed, per the skill's own dimension 11.
See `.github/workflows/ci.yml`.

**One of those gates was added because its own absence proved the point.** `ruff` was listed in the
toolkit above and recommended to every submission, but CI never ran it — so three lint findings sat
in a shipped semgrep fixture through four passes of work with nothing to catch them. That is the
overstated-coverage failure this skill audits others for (dimension 12), committed here. It now runs
pinned, with the fixtures deliberately **in** scope: a planted defect is a *security* shape, not a
formatting one, and a fixture is still code a contributor reads. A genuine conflict gets a narrow
`# noqa: <code>` with its reason, never a widened exclude.

**The rule gates are themselves gated, because every semgrep failure mode here is a silent zero.**
`semgrep test` exits 0 when it finds no fixtures at all, and `semgrep validate` exits 0 while
printing "Configuration is invalid" — so the gates read output text, never exit codes. semgrep is
pinned (`==1.172.0`) and CI **fails if the rule gates report themselves as skipped**, so an install
that quietly didn't take effect can't pass as a clean run. Gate 5 applies dimension 11 to the rules
reflexively: for each of 40 rows it removes one planted defect from a fixture and requires exactly
one finding to disappear, with negative-control rows that mutate an incidental value and require the
finding to *remain*. A rule that survives its own defect removal matches the file, not the defect.

## Known limitations

- It is a **procedure that guides an assistant**, not a static analyzer — its thoroughness
  depends on the assistant executing the probes. Treat its verdict as a strong pre-check, not
  a certification.
- The Exchange checklist evolves; the copy embedded in `SKILL.md` is a snapshot. The skill
  fetches the live version and defers to it.
- It cannot replace the Exchange's **two-human reviewer** sign-off.

## Project

- [CHANGELOG.md](./CHANGELOG.md) — release history (SemVer).
- [CONTRIBUTING.md](./CONTRIBUTING.md) — how to propose changes and the bar they must meet.
- [SECURITY.md](./SECURITY.md) — how to report a security issue.
- [examples/sample-review.md](./examples/sample-review.md) — illustrative output.

## License

[MIT](./LICENSE) © 2026 Tenable, Inc.
