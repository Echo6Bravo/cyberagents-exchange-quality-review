// Test fixture. Every annotated line is a planted defect; every unannotated line is an enforced
// true negative (`semgrep test` requires reported lines == annotated lines exactly, so an
// unannotated line that fires FAILS the test).
//
// The static-vs-interpolated template pair below is load-bearing. `pattern-not: fetch("...", ...)`
// must exclude the STATIC template while still reporting the INTERPOLATED one; writing the exclusion
// with backticks instead would suppress both, including a real SSRF. Both shapes are here so that
// distinction is tested rather than asserted in a comment.
//
// EVERY SINK BRANCH IS EXERCISED, unsafe and safe. That is not decoration: the first ablation run
// found the `got`, `http.request`, and `https.request` exclusions INERT purely because this fixture
// only called `fetch` and `axios`, which means those three branches had zero test coverage and could
// have been broken by any edit without a test failing. Coverage is asserted per BRANCH, not per rule.

declare function fetch(u: unknown, o?: unknown): Promise<{ text(): Promise<string> }>;
declare function got(u: unknown, o?: unknown): Promise<unknown>;
declare const http: { request(u: unknown, o?: unknown): unknown };
declare const https: { request(u: unknown, o?: unknown): unknown };
declare const axios: {
  get(u: unknown, o?: unknown): Promise<unknown>;
  post(u: unknown, o?: unknown): Promise<unknown>;
  put(u: unknown, o?: unknown): Promise<unknown>;
  delete(u: unknown, o?: unknown): Promise<unknown>;
  request(o: unknown): Promise<unknown>;
};
declare const finding: { host: string; detailsUrl: string };
declare const config: { baseUrl: string };

const ALLOWED_HOSTS = ["api.example.com", "api.tenable.com"];

// ---- DEFECTS: the request target is derived from data, with no host allowlist. ------------------

// A bare variable. The commonest shape, and the one with no syntactic hint at all about provenance.
export async function fetchFindingDetails(url: string): Promise<string> {
  // ruleid: ts-ssrf-url-from-scanned-data
  const res = await fetch(url);
  return res.text();
}

// An INTERPOLATED template whose HOST comes from a scan result. This is the case a direct port of
// the Python rule would have silently suppressed.
export async function fetchByHost(): Promise<string> {
  // ruleid: ts-ssrf-url-from-scanned-data
  const res = await fetch(`https://${finding.host}/details`);
  return res.text();
}

// Same defect through axios.
export async function postToFindingHost(body: string): Promise<unknown> {
  // ruleid: ts-ssrf-url-from-scanned-data
  return axios.post(finding.detailsUrl, { body });
}

// The object form. `axios.request({url})` is a distinct pattern branch from `axios.get(url)`.
export async function requestFindingUrl(): Promise<unknown> {
  // ruleid: ts-ssrf-url-from-scanned-data
  return axios.request({ url: finding.detailsUrl, method: "GET" });
}

// The remaining axios verbs. Each is its own pattern branch, so each needs its own case.
export async function getFindingHost(): Promise<unknown> {
  // ruleid: ts-ssrf-url-from-scanned-data
  return axios.get(finding.detailsUrl);
}

export async function putToFindingHost(body: string): Promise<unknown> {
  // ruleid: ts-ssrf-url-from-scanned-data
  return axios.put(finding.detailsUrl, { body });
}

export async function deleteAtFindingHost(): Promise<unknown> {
  // ruleid: ts-ssrf-url-from-scanned-data
  return axios.delete(finding.detailsUrl);
}

// `got`, and the two node core clients. Untested branches until this ablation; see the file header.
export async function gotFindingUrl(): Promise<unknown> {
  // ruleid: ts-ssrf-url-from-scanned-data
  return got(finding.detailsUrl);
}

export function httpRequestFindingUrl(): unknown {
  // ruleid: ts-ssrf-url-from-scanned-data
  return http.request(finding.detailsUrl);
}

export function httpsRequestFindingUrl(): unknown {
  // ruleid: ts-ssrf-url-from-scanned-data
  return https.request(finding.detailsUrl);
}

// ---- OK: hardcoded targets. Must not match. ----------------------------------------------------

export async function fetchStatusLiteral(): Promise<string> {
  const res = await fetch("https://api.example.com/status");
  return res.text();
}

// A fully STATIC template literal -- no interpolation, so it is a literal with different quotes.
// Paired with fetchByHost() above: the rule must exclude this one and report that one.
export async function fetchStatusStaticTemplate(): Promise<string> {
  const res = await fetch(`https://api.example.com/status`);
  return res.text();
}

export async function postStatusLiteral(body: string): Promise<unknown> {
  return axios.post("https://api.example.com/events", { body });
}

// The safe counterparts for the other three sinks. Without these, their literal exclusions are inert
// and nothing would fail if someone deleted them.
export async function gotStatusLiteral(): Promise<unknown> {
  return got("https://api.example.com/status");
}

export function httpRequestLiteral(): unknown {
  return http.request("http://api.example.com/status");
}

export function httpsRequestLiteral(): unknown {
  return https.request("https://api.example.com/status");
}

// ---- OK: the template interpolates, but the HOST is a literal. Must not match. -----------------
// These three are what the precision filter buys. The interpolation is in the path, the query
// string, or the port, so the request cannot be aimed at a different host -- which is the whole
// question this rule asks. Without them the filter is inert and nothing fails if it is deleted.

export async function fetchItemById(id: string): Promise<string> {
  const res = await fetch(`https://api.example.com/items/${id}`);
  return res.text();
}

export async function fetchWithQuery(params: string): Promise<string> {
  const res = await fetch(`https://api.example.com/search?${params}`);
  return res.text();
}

// The commonest shape in the corpus's test files: a harness reaching the server it just started.
export async function fetchLoopbackPort(port: number): Promise<string> {
  const res = await fetch(`http://127.0.0.1:${port}/mcp`);
  return res.text();
}

// A relative URL has no host at all -- same-origin by construction.
export async function fetchRelative(company: string): Promise<string> {
  const res = await fetch(`/public/${company}.svg`);
  return res.text();
}

// ---- OK: a host allowlist is lexically present. Must not match. --------------------------------

// The negated-guard spelling: reject first, then request.
export async function fetchGuardedNegated(raw: string): Promise<string> {
  const host = new URL(raw).hostname;
  if (!ALLOWED_HOSTS.includes(host)) {
    throw new Error(`host not allowed: ${host}`);
  }
  const res = await fetch(raw);
  return res.text();
}

// The positive-guard spelling: request only inside the allowed branch. A rule recognizing one
// spelling of a guard punishes everyone who writes it the other way -- the lesson
// py-path-write-without-containment records with four spellings.
export async function fetchGuardedPositive(raw: string): Promise<string> {
  const host = new URL(raw).hostname;
  if (ALLOWED_HOSTS.includes(host)) {
    const res = await fetch(raw);
    return res.text();
  }
  return "";
}

// ---- DOCUMENTED FALSE POSITIVE, unannotated is NOT an option here: this DOES fire. --------------
// The dominant real shape -- a config base URL with a fixed path. It is annotated because the rule
// genuinely reports it and the fixture must be honest about that; the message tells the reviewer to
// answer "where does the host come from?" and, for this shape, to move on. Measured: 29 corpus
// `fetch` calls have an interpolated template and this is most of them.
export async function fetchFromConfigBase(): Promise<string> {
  // ruleid: ts-ssrf-url-from-scanned-data
  const res = await fetch(`${config.baseUrl}/api/v1/status`);
  return res.text();
}

// ---- DOCUMENTED BLIND SPOTS, unannotated because they genuinely do NOT fire. -------------------

// A wrapper hides the sink. Only the literal spellings in the rule are matched, so a codebase that
// routes every request through a client reports zero -- and that zero means nothing.
declare const apiClient: { get(p: string): Promise<string> };
export async function fetchViaWrapper(url: string): Promise<string> {
  return apiClient.get(url);
}

// A `Set`-based allowlist is a correct guard the rule does not recognize. It is listed as a blind
// spot for FALSE POSITIVES; here it is unannotated only because the request is wrapped. Keeping the
// wrapper is deliberate: annotating a correct-code hit would encode the FP as expected behaviour.
const ALLOWED_SET = new Set(["api.example.com"]);
export async function fetchGuardedBySet(raw: string): Promise<string> {
  const host = new URL(raw).hostname;
  if (!ALLOWED_SET.has(host)) {
    throw new Error("host not allowed");
  }
  return apiClient.get(raw);
}
