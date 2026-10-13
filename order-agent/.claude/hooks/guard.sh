#!/usr/bin/env bash
# HOOK — a guarantee, not a request.
# Claude Code runs this before every Bash call (wired up in settings.json next to this file).
# Exit 2 = the call is blocked; whatever we print to stderr is handed to the model as the reason.
#
# Two jobs:
#   1. The MODEL must never add --confirm to a write script. --confirm is the human's to add.
#      This hook blocks any agent-issued command that contains --confirm, so the human stays
#      in the loop even though the write scripts are "allowed".
#   2. Block raw infra mutation / env dumps, in case the model reaches for them directly.
#
# Try it with no API key and no agent at all:
#   echo '{"tool_name":"Bash","tool_input":{"command":"./scripts/trigger-remediation.sh d PL a b k.txt --confirm"}}' | ./guard.sh; echo "exit $?"
#
# Needs jq. A guardrail, not a sandbox: the real safety is that the write scripts are dry-run
# and the session holds no kube/prod credentials.

cmd=$(jq -r '.tool_input.command // empty')

# 1 · the model may NOT self-confirm a write
if printf '%s' "$cmd" | grep -Eq -- '--confirm'; then
  echo "Blocked by guard.sh: '--confirm' is the human's to add, not the agent's. Present the write for approval; a person re-runs it with --confirm." >&2
  exit 2
fi

# 2 · no raw infrastructure mutation or environment dump
block='terraform +(apply|destroy)|kubectl +(apply|delete|scale|edit|patch|drain)|helm +(install|upgrade|uninstall)|git +push|rm +-rf|(^|[;&| ])(env|printenv)( |$)'
if printf '%s' "$cmd" | grep -Eq "$block"; then
  echo "Blocked by guard.sh: '$cmd' changes infrastructure or dumps the environment. Propose it for a human instead." >&2
  exit 2
fi

exit 0
