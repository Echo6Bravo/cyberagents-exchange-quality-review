// Planted-defect fixture for ts-weak-hash-or-random (dimension 8, CWE-328 / CWE-338).
//
// The must-NOT-match lines are enforced coverage: `semgrep test` requires the reported line set to
// equal the annotated set EXACTLY, so an unannotated line that fires fails the test. This rule's
// confidence is LOW by design -- most real hits are legitimate non-security uses -- so the negative
// cases below are the ones that keep it from being noise.

import crypto from "crypto";

const body: string = "";

// The defect that matters: a weak digest used to verify an artifact's integrity, where a collision is
// something an attacker gains from.
// ruleid: ts-weak-hash-or-random
export const artifactDigest = crypto.createHash("md5").update(body).digest("hex");

// ruleid: ts-weak-hash-or-random
export const legacyDigest = crypto.createHash("sha1").update(body).digest("hex");

// Uppercase is valid Node and was measured NOT caught by the two literal patterns -- it needs the
// metavariable-regex branch. Annotated so that dropping that branch fails the test.
// ruleid: ts-weak-hash-or-random
export const shoutyDigest = crypto.createHash("MD5").update(body).digest("hex");

// A literal in a local const IS resolved (constant propagation), and specifically by the LITERAL
// branches -- the metavariable-regex branch binds the identifier and cannot see through it. Annotated
// so that "simplifying" the rule down to only the regex branch fails the test.
const HASH_ALG: string = "md5";
// ruleid: ts-weak-hash-or-random
export const indirectDigest = crypto.createHash(HASH_ALG).update(body).digest("hex");

// The RNG defect: a token minted from a non-CSPRNG. Guessable, because `Math.random()`'s state is
// recoverable from a few outputs.
// ruleid: ts-weak-hash-or-random
export const sessionToken = Math.random().toString(36).slice(2);

// ruleid: ts-weak-hash-or-random
export const requestId = Math.random().toString(16);

// OK: a strong hash. Must not match -- flagging this would punish the recommended fix.
export const goodDigest = crypto.createHash("sha256").update(body).digest("hex");

// OK: the recommended RNG. Must not match, same reason.
export const goodToken = crypto.randomBytes(32).toString("hex");
export const goodId = crypto.randomUUID();

// OK: the documented BLIND SPOT, left UNANNOTATED on purpose. `Math.random()` without `.toString(...)`
// is a perfectly good way to mint a guessable id, and this rule does not see it -- deliberately, since
// matching bare `Math.random()` would fire on every jitter and sampling call and get the rule ignored.
// A recall/precision trade, recorded rather than hidden. If a future version widens the pattern,
// `semgrep test` FAILS here and forces the blind-spot list in the .yaml to be updated.
export function weakNumericId(): number {
  return Math.floor(Math.random() * 1e9);
}

// OK: the algorithm arriving from a parameter -- past where constant propagation reaches. Measured.
export function digestWith(algorithm: string): string {
  return crypto.createHash(algorithm).update(body).digest("hex");
}

// OK: the documented FALSE-POSITIVE class, in its non-matching spelling. Jitter is a legitimate use of
// `Math.random()`, and this shape does not fire. Kept here so the fixture shows both sides of the
// triage question -- a reader who only sees the defects will over-apply the rule.
export function backoffMs(attempt: number): number {
  return 2 ** attempt * 100 + Math.random() * 50;
}
