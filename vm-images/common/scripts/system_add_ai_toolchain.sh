#!/bin/bash

# Install the AI agent toolchain for a specified user (single consolidated
# process replacing the individual per-agent provisioners).
#
# Tools installed (all per-user, so each tool can self-update):
#   claude        Anthropic Claude Code        ~/.local/bin/claude
#   pi            PI coding agent (npm)        ~/.local/bin/pi
#   codex         OpenAI Codex CLI             ~/.local/bin/codex
#   copilot       GitHub Copilot CLI (npm)     ~/.local/bin/copilot
#   gemini        Google Gemini CLI (npm)      ~/.local/bin/gemini
#   cursor-agent  Cursor Agent                 ~/.local/bin/cursor-agent
#   kimi          Kimi Code CLI                ~/.kimi-code/bin/kimi
#   opencode      OpenCode CLI                 ~/.opencode/bin/opencode
#   hermes        Nous Hermes Agent            ~/.local/bin/hermes
#   agy           Google Antigravity CLI       ~/.local/bin/agy
#
# Usage:
#   system_add_ai_toolchain.sh [username]
#   DB_USERNAME=ubuntu system_add_ai_toolchain.sh
#
# Requires: Node.js in /usr/local (system_add_nodejs.sh) for the npm-based
# tools (pi, copilot, gemini).
#
# Auth/config for every tool is a runtime concern (each has its own login
# flow); nothing credential-related is baked.
#
# Versioning policy: every tool installs its latest stable release at build
# time via the vendor's official channel (native installer, GitHub latest
# release, or registry default) — nothing is version-pinned here. Tradeoff:
# two builds on different days may bake different versions, so the image is
# not byte-reproducible. Instead of silently pinning stale versions, the
# resolved versions are captured in the build output (see the report at the
# end of this script) and each tool's version command is asserted by the
# platform goss tests, so what was baked is always recoverable from the
# build/test artifacts.

set -euo pipefail

# Accept username as parameter or environment variable
DB_USERNAME="${1:-${DB_USERNAME:?Set DB_USERNAME or pass a username argument}}"

# Validate username (lowercase alphanumeric, underscore, hyphen)
if ! [[ "${DB_USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: Invalid username '${DB_USERNAME}'."
  exit 1
fi

# Verify user exists
if ! id -u "${DB_USERNAME}" > /dev/null 2>&1; then
  echo "ERROR: User '${DB_USERNAME}' does not exist. Please create the user first."
  exit 1
fi

echo "Executing system_add_ai_toolchain.sh for user '${DB_USERNAME}'..."

USER_HOME=$(eval echo "~${DB_USERNAME}")

# Run a command as the target user with HOME set and /usr/local/bin on PATH
# (sudo resets PATH to secure_path, which breaks npm's env-node shebang and
# installers that probe for node/uv).
run_as_user() {
  sudo -u "${DB_USERNAME}" env HOME="${USER_HOME}" PATH="/usr/local/bin:${PATH}" "$@"
}

# Verify npm is available for the npm-based tools
if ! command -v /usr/local/bin/npm > /dev/null 2>&1; then
  echo "ERROR: npm is not installed. Install Node.js first (system_add_nodejs.sh)."
  exit 1
fi
echo "Using Node: $(/usr/local/bin/node --version), npm: $(/usr/local/bin/npm --version)"

run_as_user mkdir -p "${USER_HOME}/.local/bin"

# Add ~/.local/bin to PATH in .bashrc if not already present
if ! run_as_user grep -q '\.local/bin' "${USER_HOME}/.bashrc" 2>/dev/null; then
  run_as_user tee -a "${USER_HOME}/.bashrc" > /dev/null <<'EOF'

# User-local binaries (AI toolchain, npm --prefix ~/.local installs, etc.)
export PATH="$HOME/.local/bin:$PATH"
EOF
  echo "Added ~/.local/bin to PATH in .bashrc"
fi

# ---------------------------------------------------------------------------
# Installers — each echoes a section header so build logs are searchable
# ---------------------------------------------------------------------------

echo "=== [1/10] claude (Anthropic Claude Code, native installer) ==="
run_as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

echo "=== [2/10] pi (PI coding agent, npm) ==="
run_as_user /usr/local/bin/npm install -g --prefix "${USER_HOME}/.local" @earendil-works/pi-coding-agent

echo "=== [3/10] codex (OpenAI Codex CLI) ==="
run_as_user bash -c 'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh'

echo "=== [4/10] copilot (GitHub Copilot CLI, npm) ==="
run_as_user /usr/local/bin/npm install -g --prefix "${USER_HOME}/.local" @github/copilot

echo "=== [5/10] gemini (Google Gemini CLI, npm) ==="
run_as_user /usr/local/bin/npm install -g --prefix "${USER_HOME}/.local" @google/gemini-cli@latest

echo "=== [6/10] cursor-agent (Cursor Agent) ==="
run_as_user bash -c 'curl -fsSL https://cursor.com/install | bash'

echo "=== [7/10] kimi (Kimi Code CLI) ==="
run_as_user bash -c 'curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash'

echo "=== [8/10] opencode (OpenCode CLI) ==="
run_as_user bash -c 'curl -fsSL https://opencode.ai/install | bash'

echo "=== [9/10] hermes (Nous Hermes Agent) ==="
# Setup wizard and Playwright/Chromium browser install are runtime concerns
# (browser adds hundreds of MB; install later with the installer's
# --ensure browser if needed).
run_as_user bash -c \
  'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-browser --non-interactive'

echo "=== [10/10] agy (Google Antigravity CLI) ==="
run_as_user bash -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash'

# ---------------------------------------------------------------------------
# Verification — every binary must exist and be executable
# ---------------------------------------------------------------------------

echo "=== Verifying AI toolchain binaries ==="
FAILED=0
for BIN in \
  "${USER_HOME}/.local/bin/claude" \
  "${USER_HOME}/.local/bin/pi" \
  "${USER_HOME}/.local/bin/codex" \
  "${USER_HOME}/.local/bin/copilot" \
  "${USER_HOME}/.local/bin/gemini" \
  "${USER_HOME}/.local/bin/cursor-agent" \
  "${USER_HOME}/.kimi-code/bin/kimi" \
  "${USER_HOME}/.opencode/bin/opencode" \
  "${USER_HOME}/.local/bin/hermes" \
  "${USER_HOME}/.local/bin/agy"
do
  if run_as_user test -x "${BIN}"; then
    echo "OK:      ${BIN}"
  else
    echo "MISSING: ${BIN}"
    FAILED=1
  fi
done

if [ "${FAILED}" -ne 0 ]; then
  echo "ERROR: One or more AI toolchain binaries missing for user '${DB_USERNAME}'."
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolved-version report — best-effort, never fails the build
# ---------------------------------------------------------------------------
# Captures the exact versions this build resolved (see "Versioning policy"
# above). Each command runs with stdin closed and a timeout: some agent CLIs
# block or fail without a TTY in the packer provisioner session (agy is
# bubbletea-based: "error opening TTY: could not open TTY: open /dev/tty:
# no such device or address"), so a missing entry here is tolerated — the
# executable check above is the hard gate.
echo "=== Resolved AI toolchain versions for '${DB_USERNAME}' (build-time snapshot) ==="
report_version() {
  local name="$1"
  shift
  local output
  if output=$(run_as_user timeout 30 "$@" < /dev/null 2>&1); then
    echo "VERSION ${name}: $(printf '%s\n' "${output}" | head -1)"
  else
    echo "VERSION ${name}: version command unavailable non-interactively (binary verified executable above)"
  fi
}
report_version claude       "${USER_HOME}/.local/bin/claude" --version
report_version pi           "${USER_HOME}/.local/bin/pi" --version
report_version codex        "${USER_HOME}/.local/bin/codex" --version
report_version copilot      "${USER_HOME}/.local/bin/copilot" --version
report_version gemini       "${USER_HOME}/.local/bin/gemini" --version
report_version cursor-agent "${USER_HOME}/.local/bin/cursor-agent" --version
report_version kimi         "${USER_HOME}/.kimi-code/bin/kimi" --version
report_version opencode     "${USER_HOME}/.opencode/bin/opencode" --version
report_version hermes       "${USER_HOME}/.local/bin/hermes" --version
report_version agy          "${USER_HOME}/.local/bin/agy" --version

echo "system_add_ai_toolchain.sh execution completed."
