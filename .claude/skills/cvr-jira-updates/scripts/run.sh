#!/bin/sh
# Runs the cvr-jira-updates skill headlessly. launchd fires this every quarter hour;
# the guard limits real runs to weekdays 09:00-17:30 local time.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

[ "$(date +%u)" -le 5 ] || exit 0
now=$(date +%H%M)
[ "$now" -ge 0900 ] && [ "$now" -le 1730 ] || exit 0

echo "--- $(date -Iseconds)"
cd "$HOME"
claude -p "Run the cvr-jira-updates skill now. Do not ask questions; if a step cannot complete, say why and stop." \
  --allowedTools "Skill,Bash,Read,Write,mcp__jira__*"
