// Planted-defect fixture for ts-wildcard-cors (dimension 17, CWE-942).
//
// The must-NOT-match lines are enforced coverage, not decoration: `semgrep test` requires the
// reported line set to equal the annotated line set EXACTLY, so an unannotated line that fires fails
// the test. That is what keeps the "correct spelling" cases below from silently starting to match.

import express from "express";
import cors from "cors";

const app = express();
const ALLOWED_ORIGIN: string = process.env.ALLOWED_ORIGIN ?? "https://app.example.com";

app.use((req, res, next) => {
  // ruleid: ts-wildcard-cors
  res.setHeader("Access-Control-Allow-Origin", "*");
  next();
});

app.get("/findings", (req, res) => {
  // ruleid: ts-wildcard-cors
  res.header("Access-Control-Allow-Origin", "*");
  res.json({ findings: [] });
});

// ruleid: ts-wildcard-cors
app.use(cors({ origin: "*" }));

// The boolean spelling of the same thing: reflect whatever origin asked. Flagged deliberately -- it
// reads as more restrained than `"*"` and is not.
// ruleid: ts-wildcard-cors
app.use(cors({ origin: true }));

// Bare `cors()` defaults to `*`. This is the commonest real spelling, because it looks like a default
// rather than a decision.
// ruleid: ts-wildcard-cors
app.use(cors());

// OK: a named origin. Must not match -- a pattern keyed on the header name alone would flag this and
// punish the correct spelling.
app.use(cors({ origin: ALLOWED_ORIGIN }));

// OK: the explicit allowlist form.
app.use(cors({ origin: ["https://app.example.com", "https://admin.example.com"] }));

// OK: a different header that happens to carry a `*`. Guards against a value-keyed pattern.
app.get("/health", (req, res) => {
  res.setHeader("Vary", "*");
  res.send("ok");
});

// A wildcard held in a local variable IS still caught -- semgrep does constant propagation, so the
// indirection buys nothing. Annotated because it is a real shape and because an earlier draft of this
// fixture asserted the opposite: it listed this as a blind spot, and `semgrep test` reported it as an
// unexpected finding. The test corrected the documentation, which is the point of having it.
export function permissiveViaLocalConst(res: any): void {
  const acao: string = "*";
  // ruleid: ts-wildcard-cors
  res.setHeader("Access-Control-Allow-Origin", acao);
}

// OK: the documented BLIND SPOTS, kept visible on purpose and left UNANNOTATED. Constant propagation
// stops at a value it cannot resolve -- a parameter, or an expression like `?? "*"` -- so both of
// these are wildcards this rule does not see. Measured, not assumed. If a future rule version learns
// to reach them, `semgrep test` FAILS here, which forces the blind-spot list in the .yaml to be
// updated instead of quietly going stale.
export function permissiveViaParameter(res: any, acao: string): void {
  res.setHeader("Access-Control-Allow-Origin", acao);
}

export function permissiveViaEnvFallback(res: any): void {
  const acao: string = process.env.ACAO ?? "*";
  res.setHeader("Access-Control-Allow-Origin", acao);
}
