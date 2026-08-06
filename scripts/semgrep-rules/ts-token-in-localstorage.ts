// Test fixture for ts-token-in-localstorage. The comment annotations below are the contract: a
// "ruleid" annotation marks the next line as one that MUST match, an "ok" annotation marks the next
// line as one that must NOT match. (Spelled out in prose here on purpose -- writing those markers
// literally in this header would make semgrep try to parse them as annotations and warn.)
// `semgrep test` requires expected == reported EXACTLY, so any UNannotated line that fires also
// fails the test. That is what makes the near-misses below real true-negative coverage.
//
// No real credentials here: values come from function params or env, never literals. gitleaks
// scans full history, so a credential-shaped literal committed once is a permanent build failure.

declare const localStorage: any;
declare const sessionStorage: any;
declare const window: any;
declare const chrome: any;
declare const process: any;

export function saveAuth(accessToken: string, refreshToken: string, theme: string) {
  // ruleid: ts-token-in-localstorage
  localStorage.setItem("access_token", accessToken);

  // ruleid: ts-token-in-localstorage
  localStorage.setItem("apiKey", process.env.SERVICE_KEY);

  // ruleid: ts-token-in-localstorage
  sessionStorage.setItem("user_password", "");

  // ruleid: ts-token-in-localstorage
  window.localStorage.setItem("REFRESH_TOKEN", refreshToken);

  // ruleid: ts-token-in-localstorage
  localStorage["bearer"] = accessToken;

  // ruleid: ts-token-in-localstorage
  chrome.storage.local.set({ authToken: accessToken });

  // --- near misses: persistent storage, but the key is not credential-shaped. These are the
  // --- true-negative controls. If the regex is widened carelessly, `semgrep test` fails here.

  // ok: ts-token-in-localstorage
  localStorage.setItem("theme", theme);

  // ok: ts-token-in-localstorage
  localStorage.setItem("lastVisitedPage", "/dashboard");

  // ok: ts-token-in-localstorage
  localStorage.removeItem("access_token");

  // ok: ts-token-in-localstorage
  const t = localStorage.getItem("access_token");

  // ok: ts-token-in-localstorage
  chrome.storage.local.set({ sidebarWidth: 240 });

  // ok: ts-token-in-localstorage
  const inMemoryToken = accessToken;

  return { t, inMemoryToken };
}
