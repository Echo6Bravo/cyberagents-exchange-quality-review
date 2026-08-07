// Test fixture. Every annotated line is a planted defect; every unannotated line is an enforced
// true negative (`semgrep test` requires reported lines == annotated lines exactly, so an
// unannotated line that fires FAILS the test).
//
// The three guard spellings below are the ones MEASURED in the 1074-file MCP corpus, not invented:
// `startsWith(resolve(DIR) + sep)`, `startsWith(ROOT + path.sep)`, and
// `path.relative(base, dest).startsWith("..")`. Each appears here in the form real code uses, because
// each is a separate pattern and a rule recognizing only one punishes everyone who writes it another
// way -- the lesson py-path-write-without-containment records with four Python spellings.
//
// EVERY SINK BRANCH IS EXERCISED, unsafe AND safe. That is not decoration: an ablation of the SSRF
// sibling found three exclusions inert purely because its fixture called only two of its sinks, which
// left those branches with zero committed coverage. Coverage is asserted per BRANCH, not per rule.

import fs from "fs";
import path from "path";
import { resolve, sep } from "path";

declare const finding: { path: string; name: string };
const OUT = "/var/tmp/reports";
const DOCS_ROOT = "/srv/docs";

// ---- DEFECTS: a path component is data-derived, with no containment guard. ----------------------

// A bare variable. The commonest shape, and no syntactic hint of provenance at all.
export function writeFindingReport(body: string): void {
  // ruleid: ts-path-write-without-containment
  fs.writeFileSync(finding.path, body);
}

// Joined with an untrusted name. `path.join` does NOT contain -- it happily resolves `../../etc`.
export function writeNamedReport(body: string): void {
  // ruleid: ts-path-write-without-containment
  fs.writeFileSync(path.join(OUT, finding.name), body);
}

// An INTERPOLATED template still fires; only a static one is excluded. This is what keeps a
// formatting cleanup from silently disabling the rule.
export function writeInterpolatedName(body: string): void {
  // ruleid: ts-path-write-without-containment
  fs.writeFileSync(`${OUT}/remediate-${finding.name}.tf`, body);
}

// The remaining sink branches. Each is its own pattern, so each needs its own case.
export function appendFindingLog(line: string): void {
  // ruleid: ts-path-write-without-containment
  fs.appendFileSync(finding.path, line);
}

export function appendFindingLogAsync(line: string): void {
  // ruleid: ts-path-write-without-containment
  fs.appendFile(finding.path, line, () => undefined);
}

export function writeFindingAsync(body: string): void {
  // ruleid: ts-path-write-without-containment
  fs.writeFile(finding.path, body, () => undefined);
}

export function streamFindingReport(): unknown {
  // ruleid: ts-path-write-without-containment
  return fs.createWriteStream(finding.path);
}

export async function writeFindingPromise(body: string): Promise<void> {
  // ruleid: ts-path-write-without-containment
  return fs.promises.writeFile(finding.path, body);
}

export async function appendFindingPromise(line: string): Promise<void> {
  // ruleid: ts-path-write-without-containment
  return fs.promises.appendFile(finding.path, line);
}

// ---- OK: hardcoded filenames. Must not match. --------------------------------------------------

export function writeManifestLiteral(body: string): void {
  fs.writeFileSync("/var/tmp/reports/manifest.json", body);
}

// A fully STATIC template literal -- a literal with different quotes. Paired with
// writeInterpolatedName() above: the rule must exclude this and report that.
export function writeManifestStaticTemplate(body: string): void {
  fs.writeFileSync(`/var/tmp/reports/manifest.json`, body);
}

export function writeManifestJoined(body: string): void {
  fs.writeFileSync(path.join(OUT, "manifest.json"), body);
}

export async function writeManifestPromise(body: string): Promise<void> {
  return fs.promises.writeFile("/var/tmp/reports/manifest.json", body);
}

export async function writeManifestPromiseJoined(body: string): Promise<void> {
  return fs.promises.writeFile(path.join(OUT, "manifest.json"), body);
}

// ---- OK: a containment guard is lexically present. Must not match. -----------------------------

// Spelling 1, negated: resolve then compare with the separator appended. Note the `+ sep` -- WITHOUT
// it, `/var/tmp/reports-evil` would pass. The rule cannot tell the two apart; see the rule header.
export function writeGuardedResolveSep(name: string, body: string): void {
  const dest = path.resolve(OUT, name);
  if (!dest.startsWith(resolve(OUT) + sep)) {
    throw new Error(`path escapes ${OUT}`);
  }
  fs.writeFileSync(dest, body);
}

// Spelling 2, negated: a root constant plus `path.sep`.
export function writeGuardedRootSep(name: string, body: string): void {
  const requested = path.resolve(DOCS_ROOT, name);
  if (!requested.startsWith(DOCS_ROOT + path.sep)) {
    throw new Error("path escapes the docs root");
  }
  fs.writeFileSync(requested, body);
}

// Spelling 3: `path.relative` starting with ".." means the target is outside the base.
export function writeGuardedRelative(name: string, body: string): void {
  const dest = path.resolve(OUT, name);
  if (path.relative(OUT, dest).startsWith("..")) {
    throw new Error("path escapes the output dir");
  }
  fs.writeFileSync(dest, body);
}

// The positive-guard spelling: write only inside the allowed branch.
export function writeGuardedPositive(name: string, body: string): void {
  const dest = path.resolve(OUT, name);
  if (dest.startsWith(resolve(OUT) + sep)) {
    fs.writeFileSync(dest, body);
  }
}

// ---- DOCUMENTED BLIND SPOTS, unannotated because they genuinely do NOT fire. -------------------

// A BARE import of `writeFile`, not `fs.`-qualified. This is the most likely reason for a false clean
// bill of health from this rule: a codebase importing `{ writeFile } from "node:fs/promises"` reports
// zero and that zero means nothing. Recorded as a gap rather than a claim.
import { writeFile as bareWriteFile } from "node:fs/promises";
export async function writeViaBareImport(body: string): Promise<void> {
  return bareWriteFile(finding.path, body);
}

// `fs.mkdir`, `fs.rename`, `fs.copyFile`, and archive extraction are all traversal sinks that are NOT
// matched. Extraction is the classic one -- an archive entry named `../../etc/cron.d/x`.
export function renameIntoFindingPath(): void {
  fs.renameSync("/tmp/staged", finding.path);
}

// A guard spelling the rule does not recognize. It is CORRECT code, so it is a false positive the
// rule would report -- and it is kept unannotated only because the write is a bare import, above the
// rule's sink list. Annotating a correct-code hit would encode the FP as expected behaviour.
export async function writeGuardedByIsAbsolute(name: string, body: string): Promise<void> {
  if (path.isAbsolute(name) || name.includes("..")) {
    throw new Error("rejected");
  }
  return bareWriteFile(path.join(OUT, name), body);
}
