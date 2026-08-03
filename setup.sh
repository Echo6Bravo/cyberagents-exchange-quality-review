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

# gitleaks/ruff/shellcheck/actionlint via brew; bandit via pipx/pip (handled separately below).
BREW_TOOLS="gitleaks ruff shellcheck actionlint"

have() { command -v "$1" >/dev/null 2>&1; }

report() {
  echo "== quality-review toolkit status =="
  for t in gitleaks ruff bandit shellcheck actionlint; do
    if have "$t"; then echo "  [present] $t ($($t --version 2>&1 | head -1 | tr -d '\n'))"
    else echo "  [MISSING] $t"; fi
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
  echo "    gitleaks, ruff, shellcheck, actionlint" >&2
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
