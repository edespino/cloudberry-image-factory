#!/bin/bash

# Configure Claude Code CLI settings for a specified user
# Deploys CLAUDE.md, settings.json, and keybindings.json to ~/.claude/
#
# Usage:
#   system_configure_claude.sh [username]
#   DB_USERNAME=gpadmin system_configure_claude.sh
#
# Requires: User must already exist (run after system_adduser_dbadmin.sh)

set -euo pipefail

# Accept username as parameter or environment variable, default to gpadmin
DB_USERNAME="${1:-${DB_USERNAME:-gpadmin}}"

# Validate username (alphanumeric and underscore only)
if ! [[ "${DB_USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: Invalid username '${DB_USERNAME}'. Must start with lowercase letter or underscore and contain only lowercase letters, numbers, underscores, or hyphens."
  exit 1
fi

# Verify user exists
if ! id -u "${DB_USERNAME}" > /dev/null 2>&1; then
  echo "ERROR: User '${DB_USERNAME}' does not exist. Please create the user first."
  exit 1
fi

echo "Executing system_configure_claude.sh for user '${DB_USERNAME}'..."

USER_HOME=$(eval echo "~${DB_USERNAME}")
CLAUDE_DIR="${USER_HOME}/.claude"

# Create ~/.claude/ directory
sudo -u "${DB_USERNAME}" mkdir -p "${CLAUDE_DIR}"
sudo chmod 700 "${CLAUDE_DIR}"

# Deploy CLAUDE.md
sudo -u "${DB_USERNAME}" tee "${CLAUDE_DIR}/CLAUDE.md" > /dev/null <<'CLAUDE_MD_EOF'
# Claude Code Global Preferences

Personal preferences applied to all Claude Code sessions.

---

## No Fabrication

- **NEVER fabricate information** - names, dates, IDs, quotes, or any detail not explicitly provided
- If information is needed: **ASK**
- If a template field cannot be filled: **LEAVE BLANK or ASK**
- **Review existing files before creating new ones** - When adding to a directory, READ an existing file first to learn the format
- **Speculation is acceptable** only if clearly labeled as from Claude Code AND user approves it

### Zero Tolerance for Guessing

- **Before ANY command or action:** Ask yourself "Is this documented or am I guessing?"
- **If guessing:** STOP immediately and ask for the correct approach
- **Do NOT:** Try multiple attempts with fabricated parameters hoping one works
- **Violations are logged:** See `~/.claude/principle-violations.md`

---

## Feedback Files

- **All feedback uses Slack markdown format** - `*Bold Section:*` headers, `•` bullets
- Review existing files in the feedback directory for structure examples

---

## Communication Style

- **No apologies** - Never "I apologize", "I'm sorry"
- **No validation phrases** - Never "You're right", "Great point", "Good call", "Fair point", "Valid observation"
- **No hedging** - Never "I think", "Maybe", "Perhaps"
- **No emotional language** - Never "Happy to", "Unfortunately"
- **No conversational filler** - Never "Understood", "Got it", "Makes sense", "Absolutely"
- **No human mimicry** - Do not simulate empathy, agreement, or social rapport. Be a tool, not a conversationalist.
- **Ask confirmation before commands** - All builds, deploys, git, AWS, kubectl, etc.
- **No status conclusions** - Never add "Complete", "Ready", "Finished" unless explicitly stated
- **No timeline estimates** - Never "2-3 weeks", "Week 1-12"
- When uncertain: say "I don't know"
- When wrong: state the error, state the correction

### Response Format

- **Direct and factual** - State what was done, what will be done, or what the issue is
- **No preamble** - Do not restate the user's question or lead with filler
- **No sign-off** - Do not end with "Let me know" or "Want me to proceed?"  unless a genuine decision point exists
- **These rules apply to EVERY response** - No drift over long sessions. Re-read this section if unsure.

---

## Git

- **NEVER modify git config** - Use existing global config
- **NEVER run `git config` commands**
- Commits attributed to user, not Claude
CLAUDE_MD_EOF

# Deploy settings.json
sudo -u "${DB_USERNAME}" tee "${CLAUDE_DIR}/settings.json" > /dev/null <<'SETTINGS_EOF'
{
  "includeCoAuthoredBy": false
}
SETTINGS_EOF

# Deploy keybindings.json
sudo -u "${DB_USERNAME}" tee "${CLAUDE_DIR}/keybindings.json" > /dev/null <<'KEYBINDINGS_EOF'
{
  "$schema": "https://platform.claude.com/docs/schemas/claude-code/keybindings.json",
  "$docs": "https://code.claude.com/docs/en/keybindings",
  "bindings": [
    {
      "context": "Chat",
      "bindings": {
        "ctrl+g": null
      }
    }
  ]
}
KEYBINDINGS_EOF

# Set ownership
sudo chown -R "${DB_USERNAME}:${DB_USERNAME}" "${CLAUDE_DIR}"

echo "system_configure_claude.sh execution completed for user '${DB_USERNAME}'."
