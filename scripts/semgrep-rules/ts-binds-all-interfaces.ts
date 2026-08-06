// Planted-defect fixture for ts-binds-all-interfaces (dimension 17, CWE-1327).
//
// The must-NOT-match lines are enforced coverage: `semgrep test` requires the reported line set to
// equal the annotated set EXACTLY, so an unannotated line that fires fails the test.

import express from "express";
import * as http from "http";

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

// OK: loopback. Must not match -- a pattern keyed on `.listen(` alone would flag this and punish the
// correct spelling, which is the whole fix this rule recommends.
app.listen(PORT, "127.0.0.1");

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
