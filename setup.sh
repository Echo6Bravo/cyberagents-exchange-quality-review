#!/usr/bin/env bash
# setup.sh -- one-command install of the quality-review toolkit.
# The skill itself is just instructions; these are the scanners it drives. Everything is
# OPTIONAL (the skill degrades gracefully if a tool is missing) but a full install gives the
# deepest review. CodeQL is intentionally NOT installed here -- it runs best as a free GitHub
# Actions workflow (github/codeql-action) on the repo you're reviewing, not from a local CLI.
#
# Usage:  bash setup.sh          # install what's missing
#         bash setup.sh --check  # report what's present/missing, install nothing
set -uo pipefail

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

HERE=$(cd "$(dirname "$0")" && pwd)

# SINGLE SOURCE OF TRUTH for what the toolkit contains. report() iterates TOOLS, so a tool added
# to the install list can never be silently absent from the status output (which would understate
# coverage -- the exact overclaiming failure the skill flags in others).
TOOLS="gitleaks ruff bandit shellcheck actionlint semgrep"
# Everything in TOOLS except bandit is brew-installable; bandit goes via pipx/pip below.
BREW_TOOLS=$(echo "$TOOLS" | tr ' ' '\n' | grep -v '^bandit$' | tr '\n' ' ')

have() { command -v "$1" >/dev/null 2>&1; }

# semgrep is a three-state tool: an engine with no rules is not coverage. It ships NO bundled
# security rules, and on a TLS-intercepting network the registry (`--config p/...`) cannot be
# fetched -- measured on this machine: the fetch HANGS past 90s with no output, and has also been
# seen to fail outright with CERTIFICATE_VERIFY_FAILED. So report which rules are actually
# loadable, never just that the binary exists.
#
# Deliberately NOT probed over the network. `curl https://semgrep.dev/` returns 200 here while
# semgrep's own fetch still fails (curl trusts the system keychain; semgrep's Python stack uses
# certifi), so a reachability probe would report "registry available" and be wrong. There is also
# no bounded-timeout flag for config fetch, so a probe could stall the whole script.
# Version probe. MUST stay bounded: `semgrep --version` performs an update check over the network
# and HANGS INDEFINITELY on a network that blackholes it (measured here: >90s, no output, until
# killed). `--check` advertises itself as fast and install-nothing, so a hang is a real defect --
# hence the per-tool flag plus a hard timeout backstop for every tool. The timeout is best-effort:
# `timeout`/`gtimeout` are not POSIX-guaranteed, so fall back to the bare call when neither exists.
TIMEOUT_BIN=""
for c in timeout gtimeout; do command -v "$c" >/dev/null 2>&1 && { TIMEOUT_BIN="$c"; break; }; done

tool_version() {
  case "$1" in
    semgrep) set -- semgrep --disable-version-check --version ;;
    *)       set -- "$1" --version ;;
  esac
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" 10 "$@" 2>&1 | head -1 | tr -d '\n' || echo "version probe timed out"
  else
    "$@" 2>&1 | head -1 | tr -d '\n'
  fi
}

semgrep_state() {
  if [ -d "$HERE/scripts/semgrep-rules" ]; then
    echo "custom rules only: scripts/semgrep-rules (registry not used; see note)"
  else
    echo "engine present but NO rules loadable -> contributes NO coverage"
  fi
}

report() {
  echo "== quality-review toolkit status =="
  for t in $TOOLS; do
    if have "$t"; then
      echo "  [present] $t ($(tool_version "$t"))"
      [ "$t" = "semgrep" ] && echo "            -> $(semgrep_state)"
    else
      echo "  [MISSING] $t"
    fi
  done
  echo "  [n/a]     codeql  -> use the github/codeql-action workflow (free on public repos)"
}

if [ "$CHECK_ONLY" = "1" ]; then report; exit 0; fi

# --- install path: prefer Homebrew (mac/linuxbrew); fall back to pipx for python tools ---
if have brew; then
  MISSING=""
  for t in $BREW_TOOLS; do have "$t" || MISSING="$MISSING $t"; done
  if [ -n "$MISSING" ]; then echo "brew install$MISSING"; brew install $MISSING || true; fi
else
  echo "Homebrew not found." >&2
  echo "  Install these via your platform's package manager (apt/dnf/choco) or download binaries:" >&2
  # Derived from BREW_TOOLS, not retyped -- a hand-maintained copy drifts the moment a tool is added.
  echo "    $(echo "$BREW_TOOLS" | sed 's/ *$//; s/ /, /g')" >&2
fi

# bandit via pipx (isolated) if available, else pip --user
if ! have bandit; then
  if have pipx; then pipx install bandit || true
  elif have pip3; then pip3 install --user bandit || true
  else echo "  Could not install bandit automatically (no pipx/pip3); 'pipx install bandit'." >&2; fi
fi

echo ""
report
echo ""
echo "Done. CodeQL: add the github/codeql-action workflow to the repo you're reviewing"
echo "(free for public repos; the local CLI often can't fetch query packs behind a TLS proxy)."
echo "semgrep: this skill uses ONLY its own rules in scripts/semgrep-rules -- the hosted registry"
echo "(--config p/...) is not used and may be unreachable behind a TLS proxy. Installing semgrep"
echo "without those rules adds no coverage; 'bash setup.sh --check' says which state you're in."
