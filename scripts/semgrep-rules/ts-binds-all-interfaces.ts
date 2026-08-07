// Planted-defect fixture for ts-binds-all-interfaces (dimension 17, CWE-1327).
//
// The must-NOT-match lines are enforced coverage: `semgrep test` requires the reported line set to
// equal the annotated set EXACTLY, so an unannotated line that fires fails the test.

import express from "express";
import * as http from "http";
// The factory idiom the widened pattern targets. Imported so the fixture is real code rather than a
// snippet -- the corpus measurement that motivated it came from this exact API.
import { createMcpExpressApp } from "@modelcontextprotocol/express";

const app = express();
const PORT: number = Number(process.env.PORT ?? 3000);

// ruleid: ts-binds-all-interfaces
app.listen(PORT, "0.0.0.0");

// The callback form -- same defect, and the spelling that actually appears in generated scaffolding.
// ruleid: ts-binds-all-interfaces
app.listen(PORT, "0.0.0.0", () => {
  console.log("listening");
});

const server = http.createServer(app);
// The options-object form, which `listen($P, "0.0.0.0", ...)` does not cover on its own.
// ruleid: ts-binds-all-interfaces
server.listen({ host: "0.0.0.0", port: PORT });

// A literal held in a local const is STILL caught -- semgrep does constant propagation, so the
// indirection buys nothing. Annotated because it is a real shape and because assuming otherwise is
// exactly the mistake `semgrep test` caught in this rule set's sibling CORS fixture.
export function serveViaLocalConst(): void {
  const host: string = "0.0.0.0";
  // ruleid: ts-binds-all-interfaces
  app.listen(PORT, host);
}

// The framework-FACTORY form, which has no `.listen` receiver at all. This is the shape that made the
// rule wider: measured against 1074 real MCP-server TS files, this -- not `.listen()` -- is how the
// current MCP TypeScript SDK and its middleware packages spell a broad bind, and the earlier
// receiver-bound pattern missed all 8 real occurrences.
// ruleid: ts-binds-all-interfaces
const publicApp = createMcpExpressApp({ host: "0.0.0.0" });

// Single quotes: the corpus uses them and semgrep normalizes quote style, so this matches. Annotated
// because "it's a different quote" is exactly the kind of assumption worth pinning to a test.
// ruleid: ts-binds-all-interfaces
const singleQuoted = createMcpExpressApp({ host: '0.0.0.0' });

// A broad bind PAIRED WITH an explicit host allowlist. Still annotated -- the rule flags it and should:
// this is the documented "container that must bind broadly" false positive, and `allowedHosts` answers
// DNS-rebinding, not "who may call these tools." Most real corpus hits looked exactly like this, so the
// finding is a question ("what authenticates the caller?"), not a verdict.
// ruleid: ts-binds-all-interfaces
const guardedApp = createMcpExpressApp({ host: "0.0.0.0", allowedHosts: ["api.example.com"] });

// OK: loopback. Must not match -- a pattern keyed on `.listen(` alone would flag this and punish the
// correct spelling, which is the whole fix this rule recommends.
app.listen(PORT, "127.0.0.1");

// OK: the factory form bound to loopback. Guards the widened receiver-less pattern against becoming
// "any call with a host option" -- it must still discriminate on the ADDRESS.
const localApp = createMcpExpressApp({ host: "127.0.0.1" });

// OK: a `host` option that is not an address literal at all. The widened pattern has no receiver
// constraint, so this pins that it still cannot be satisfied by an unrelated `host:` key.
const proxied = createMcpExpressApp({ host: process.env.HOST ?? "127.0.0.1" });

// OK: the options-object form, bound correctly.
server.listen({ host: "127.0.0.1", port: PORT });

// OK: `localhost` rather than the literal address. Resolves to loopback; not the defect.
app.listen(PORT, "localhost");

// OK: the documented BLIND SPOTS, left UNANNOTATED on purpose.
//
// `listen(PORT)` with no host is the BIGGEST one and the most common real exposure: on Node this is
// effectively all-interfaces, but the defect is an ABSENCE, so there is no construct any pattern can
// match. It is here to make the limit visible in the fixture rather than only in prose -- zero hits
// from this rule is not evidence of a loopback bind.
export function serveDefaultHost(): void {
  app.listen(PORT);
}

// Unresolvable host expressions: a parameter, and an env fallback. Both measured NOT matched, which is
// where constant propagation stops. If a future rule version reaches them, `semgrep test` FAILS here
// and forces the blind-spot list in the .yaml to be updated instead of drifting out of date.
export function serveViaParameter(host: string): void {
  app.listen(PORT, host);
}

export function serveViaEnvFallback(): void {
  const host: string = process.env.HOST ?? "0.0.0.0";
  app.listen(PORT, host);
}

// The IPv6 any-address -- same exposure, different vocabulary, not matched here.
export function serveIpv6Any(): void {
  app.listen(PORT, "::");
}
