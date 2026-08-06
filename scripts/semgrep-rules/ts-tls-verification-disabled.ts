// Planted-defect fixture for ts-tls-verification-disabled (dimension 6, CWE-295).
//
// The must-NOT-match lines are enforced coverage, not decoration: an unannotated line that fires
// fails `semgrep test`, so the "correct spelling" cases below cannot silently start matching.
//
// No real credentials anywhere -- gitleaks scans full history in CI, so a fixture that trips it is a
// permanent build failure no later commit can undo. The token below is read from the environment,
// which is also the shape the skill recommends.

import * as https from "https";
import axios from "axios";

const CA_BUNDLE: string = process.env.CORP_CA_BUNDLE ?? "";
const API_TOKEN: string = process.env.API_TOKEN ?? "";

// ruleid: ts-tls-verification-disabled
export const scannerAgent = new https.Agent({ rejectUnauthorized: false });

// The shape that makes this a High rather than a nit: the same disabled verification, on a client
// that attaches a bearer token to every request. A MITM gets the token, not just the payload.
export const apiClient = axios.create({
  baseURL: "https://api.example.com",
  headers: { Authorization: `Bearer ${API_TOKEN}` },
  // ruleid: ts-tls-verification-disabled
  httpsAgent: new https.Agent({ rejectUnauthorized: false }),
});

// The "it's only for local dev" spelling -- still matched, deliberately. The env guard is real, but
// nothing on this line proves the branch is unreachable in production, which is the documented
// false-positive class: triage it by proving the guard, not by reading the comment.
export const devAgent = new https.Agent({
  // ruleid: ts-tls-verification-disabled
  rejectUnauthorized: process.env.NODE_ENV === "development" ? false : true,
});

// OK: verification explicitly on. Must not match -- an over-broad pattern keyed on the property name
// alone would flag this, which would punish the correct spelling.
export const strictAgent = new https.Agent({ rejectUnauthorized: true });

// OK: the actual fix for a corporate/self-signed CA -- trust that CA, keep verification on.
export const corpAgent = new https.Agent({ ca: CA_BUNDLE });

// OK: defaults are secure; saying nothing is saying verification stays on.
export const defaultAgent = new https.Agent({ keepAlive: true });

// OK: the documented BLIND SPOT, kept visible on purpose. Identical effect, worse (process-wide),
// but it is not a JS/TS construct so this rule cannot see it. Left unannotated so that if a future
// rule version learns to match it, `semgrep test` FAILS here and forces the blind-spot list in the
// .yaml to be updated rather than letting it drift out of date.
export function disableTlsGlobally(): void {
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
}
