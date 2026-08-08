# Fixture for docker-final-stage-runs-as-root.
#
# TWO layout facts drive everything about this file, both MEASURED, both silent when violated:
#
#  1. The extension is load-bearing. semgrep claims Dockerfile targets by EXACT filename: `Dockerfile`
#     and any `*.dockerfile` suffix ARE claimed, while `Dockerfile.dev`, `Dockerfile.prod` and
#     `Containerfile` are skipped with 0 findings, rc=0 and no notice. A fixture named
#     `Dockerfile.fixture` would scan NOTHING and the test would report a vacuous pass.
#
#  2. ONE fixture per rule. `semgrep test` uses only the file whose basename matches the rule; a
#     second `...good.dockerfile` sitting beside it was measured to be IGNORED ENTIRELY -- the check
#     still reported `passed=True` while never reading it. So every case below, positive and negative,
#     has to live in this one file.
#
# WHY THE ORDER OF THE STAGES BELOW IS NOT COSMETIC. The rule's `...` spans to END OF FILE, not to the
# end of the enclosing stage. Measured truth table on the shape `FROM $I ... USER $U`:
#
#     single stage, no USER ............................. line 1        (fires)
#     single stage, with USER ........................... none
#     builder sets USER, final does not ................. final's FROM  (fires, correctly)
#     builder does not, final sets USER ................. none
#     NEITHER stage sets USER ........................... both FROMs
#     both stages set USER .............................. none
#
# Read the 4th row carefully: a root stage followed ANYWHERE LATER in the file by a `USER` is excused.
# That is exactly right for the question this rule asks -- the FINAL stage is what ships, and nothing
# follows it, so the final stage can never be excused by something later. But it means a
# must-NOT-catch stage placed AFTER a must-catch stage would silently suppress the must-catch and the
# fixture would prove nothing. An earlier draft of this file did exactly that and measured 0 findings
# on two planted defects. Hence: the negative cases come FIRST, and the file ENDS on a root stage.
#
# Every must-catch annotation below marks a stage that MUST fire. Every unannotated stage is a
# must-NOT-catch, and the native runner enforces that for free -- `passed` requires reported lines to
# equal annotated lines EXACTLY, so an unannotated stage that fires fails the test.
#
# Prose in this file must never spell the annotation keyword followed by a colon: semgrep treats it as
# a live annotation wherever it appears, including inside a comment, and then demands a finding on the
# following line. This paragraph previously did exactly that and only escaped failing because the next
# line happened to be another comment.

# --- must-NOT-catch: drops root by name. `USER` need not be the literal last line, only the last
# --- privilege-relevant one, so the trailing CMD is deliberate.
FROM python:3.12-slim
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --create-home --uid 10001 appuser
USER appuser
CMD ["python", "-m", "server"]

# --- must-NOT-catch near-miss #1: numeric uid. This is the form hadolint's DL3066 actually ASKS for
# --- (it flagged `USER node` as a "non-numeric user-id" while staying silent on the real omission),
# --- so it must not be mistaken for an absent USER.
FROM alpine:3.20
RUN adduser -D -u 10005 runner
USER 10005
CMD ["/bin/sh", "-c", "exec /app/run"]

# --- must-NOT-catch near-miss #2: uid:gid pair, alongside an ARG-driven name. Both are real
# --- spellings in the corpus; neither is an omission.
FROM node:20
ARG APP_USER=node
RUN mkdir -p /data && chown 1000:1000 /data
USER 1000:1000
CMD ["node", "server.js"]

# --- must-NOT-catch: multi-stage where BOTH stages drop root. Guards the inverse of the final case
# --- below -- a rule that ignored `pattern-not-inside` entirely would fire on both of these.
FROM rust:1.81 AS rbuild
WORKDIR /src
RUN useradd --uid 10003 rbuilder
USER rbuilder
COPY . .
RUN cargo build --release

FROM ubuntu:24.04
COPY --from=rbuild /src/target/release/tool /usr/local/bin/tool
RUN useradd --create-home --uid 10004 svc
USER svc
ENTRYPOINT ["/usr/local/bin/tool"]

# --- must-catch: multi-stage where the BUILDER drops root and the FINAL stage does not. Only the
# --- final stage's FROM is annotated, which is what proves the builder is correctly excused rather
# --- than the rule simply flagging every FROM. Bases are DIFFERENT images here, but that is
# --- incidental -- an earlier version of this comment claimed identical bases would let the single
# --- `$I` bind across the stage boundary and excuse the defect. Ablation disproved it on four probes
# --- (including two truly identical `FROM node:20` lines); see the correction in the rule header.
FROM golang:1.23 AS builder
WORKDIR /src
RUN useradd --uid 10002 builduser
USER builduser
COPY . .
RUN go build -o /out/agent ./cmd/agent

# ruleid: docker-final-stage-runs-as-root
FROM debian:bookworm-slim
COPY --from=builder /out/agent /usr/local/bin/agent
ENTRYPOINT ["/usr/local/bin/agent"]

# --- must-catch: single stage, no USER anywhere. THE dominant real defect -- 9 of 10 Dockerfiles in
# --- the measured MCP-server corpus never drop root, and hadolint's DL3002 flagged 0 of them.
# --- This stage is LAST on purpose: nothing may follow it, or its `USER`-less-ness gets excused.
# ruleid: docker-final-stage-runs-as-root
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
CMD ["node", "dist/index.js"]
