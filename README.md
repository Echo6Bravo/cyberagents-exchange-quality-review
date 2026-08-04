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
rather than reasoning about it. It leans on a standard toolkit where available —
**gitleaks** (full-history secret scan), **ruff** + **bandit** (Python lint/SAST),
**shellcheck**, **actionlint**, and **CodeQL** (as a GitHub Action) — and treats each as a
CI gate that must stay green.

See [`examples/sample-review.md`](examples/sample-review.md) for what a run's output looks
like.

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
bash setup.sh          # installs gitleaks, ruff, bandit, shellcheck, actionlint (Homebrew/pipx)
bash setup.sh --check  # just report what's present/missing, install nothing
```

Or install manually: `brew install gitleaks ruff shellcheck actionlint` and
`pipx install bandit`.

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

This repo runs the same gates it recommends (dimensions 8, 11, 18): **gitleaks** full-history
secret scan, **actionlint** on its own workflow, and a **SKILL.md structure check** (valid
`name`/`description` frontmatter, substantive body, all 19 dimensions present, the three output
buckets in order, the severity rules stated, no leftover placeholders) plus a check that the
example review obeys the bucket structure. Each check ships with a negative control — it was
verified to *fail* when the thing it guards is removed, per the skill's own dimension 11.
See `.github/workflows/ci.yml`.

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
