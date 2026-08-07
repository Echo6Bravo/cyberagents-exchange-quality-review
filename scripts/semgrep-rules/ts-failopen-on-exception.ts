// Test fixture. Every annotated line below is a planted defect; every unannotated
// line is an enforced true negative (`semgrep test` requires reported lines == annotated lines
// exactly, so an unannotated line that fires FAILS the test).
//
// Both catch spellings appear on purpose. `catch {}` (ES2019 optional binding) and `catch (e) {}` are
// different patterns to semgrep -- measured -- so a fixture using only one spelling would let the
// missing branch ship untested. Same class of blind spot ts-binds-all-interfaces shipped with.

declare function isCompliant(cfg: string): boolean;
declare function scanFindings(target: string): string[];
declare function readManifest(p: string): string[];
declare const log: { warning: (m: string) => void; error: (m: string) => void };

// ---- DEFECTS: a security decision that fails OPEN. ------------------------------------------------

export function policyAllows(cfg: string): boolean {
  // ruleid: ts-failopen-on-exception
  try {
    return isCompliant(cfg);
  } catch {
    return true;
  }
}

// The bound-parameter spelling. A separate pattern branch is required for this.
export function policyAllowsBound(cfg: string): boolean {
  // ruleid: ts-failopen-on-exception
  try {
    return isCompliant(cfg);
  } catch (err) {
    return true; // bound catch: same defect, second pattern branch
  }
}

// The log-then-return shape: the most common real spelling, because the log line is what convinces
// the author the error was handled. The leading `...` in the pattern is what catches this.
export function findingsForTarget(target: string): string[] {
  // ruleid: ts-failopen-on-exception
  try {
    return scanFindings(target);
  } catch (err) {
    log.warning(`could not scan ${target}; continuing`);
    return [];
  }
}

export function findingsUnbound(target: string): string[] {
  // ruleid: ts-failopen-on-exception
  try {
    return scanFindings(target);
  } catch {
    return []; // unbound catch: same defect, fourth pattern branch
  }
}

// ---- OK: fails CLOSED. Must not match. -----------------------------------------------------------

// The fix for the first case: an exception means "could not determine", which is not "allowed".
export function policyAllowsStrict(cfg: string): boolean {
  try {
    return isCompliant(cfg);
  } catch (err) {
    log.error(`policy unreadable: ${String(err)}`);
    return false;
  }
}

// Rethrowing is always acceptable -- the caller decides.
export function findingsOrThrow(target: string): string[] {
  try {
    return scanFindings(target);
  } catch (err) {
    throw new Error(`scan failed for ${target}`);
  }
}

// The third-state fix: `undefined` forces the caller to handle "did not run" explicitly, so it can
// never render as "passed".
export function findingsOrUnknown(target: string): string[] | undefined {
  try {
    return scanFindings(target);
  } catch {
    return undefined;
  }
}

// DOCUMENTED BLIND SPOT, unannotated because it genuinely does NOT fire: `return null` and
// `return undefined` are excluded by design. Measured on the 1074-file MCP corpus, they are 29 of 33
// permissive catch returns and are overwhelmingly "optional value absent" -- matching them would make
// this rule ~88% noise. Recorded here so the exclusion is visible rather than implied.
export function lookupOrNull(p: string): string[] | null {
  try {
    return readManifest(p);
  } catch {
    return null;
  }
}

// DOCUMENTED BLIND SPOT: the same defect in promise-expression form. Measured absent from the corpus
// in the permissive-value shape, so it is recorded as a gap rather than guessed at.
export async function findingsViaCatchMethod(target: string): Promise<string[]> {
  return Promise.resolve(scanFindings(target)).catch(() => []);
}

// OK: a catch that returns a permissive-looking value for a genuinely absent collection. This is the
// documented FP class and it DOES fire in real code -- all 4 corpus hits are this shape. It is not
// annotated here because the pattern cannot see the difference; this comment is the record. Kept as
// prose rather than a fixture case so the fixture stays an honest set of true negatives.
