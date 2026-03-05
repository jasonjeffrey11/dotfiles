#!/bin/sh
# Robbyrussell-style status line for Claude Code

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')
dir=$(basename "$cwd")

# ANSI color codes
ESC=$(printf '\033')
GREEN="${ESC}[1;32m"
CYAN="${ESC}[0;36m"
BLUE="${ESC}[1;34m"
RED="${ESC}[0;31m"
YELLOW="${ESC}[0;33m"
RESET="${ESC}[0m"

# Build git portion if inside a git repo
git_part=""
branch=$(git -C "$cwd" -c core.hooksPath=/dev/null symbolic-ref --short HEAD 2>/dev/null)
if [ -n "$branch" ]; then
    if git -C "$cwd" -c core.hooksPath=/dev/null status --porcelain 2>/dev/null | grep -q .; then
        git_part=" ${BLUE}git:(${RED}${branch}${BLUE})${RESET} ${YELLOW}✗${RESET}"
    else
        git_part=" ${BLUE}git:(${RED}${branch}${BLUE})${RESET}"
    fi
fi

# Context usage progress bar
used=$(echo "$input" | jq '.context_window.used_percentage // 0' | cut -d. -f1)
filled=$((used / 10))
empty=$((10 - filled))
bar=""
i=0; while [ $i -lt $filled ]; do bar="${bar}▓"; i=$((i + 1)); done
i=0; while [ $i -lt $empty ]; do bar="${bar}░"; i=$((i + 1)); done
if [ "$used" -ge 80 ]; then
    bar_color="$RED"
elif [ "$used" -ge 60 ]; then
    bar_color="$YELLOW"
else
    bar_color="$GREEN"
fi

printf "${GREEN}➜${RESET}  ${CYAN}%s${RESET}%s ${bar_color}%s${RESET} %s%%" "$dir" "$git_part" "$bar" "$used"
