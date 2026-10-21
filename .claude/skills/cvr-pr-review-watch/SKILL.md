---
name: cvr-pr-review-watch
description: Watch #rush-code-review for frontend PRs (cvr-client, cvr-client-admin) that someone other than me asks to have reviewed, start a pr-review orchestrator session for each new one, and relay later posts about a PR to its orchestrator. Use when the user says "check code review for new PRs", "any new FE PRs to review", "watch rush-code-review", "start a review for cvr-client PR 600", or asks for a code-review catch-up. Read-only against Slack; keeps a last-checked timestamp locally.
---

# CVR PR review watch

Finds frontend PRs posted for review in `#rush-code-review` (channel `C0BBRHW14F9`) since the last run and starts one review orchestrator per PR. The orchestrator reviews the PR, builds the artifact JJ picks comments from, posts what JJ submits, follows the author's replies and pushes, and approves when JJ presses Approve. Its process lives in `scripts/orchestrate-pr-review.sh`.

Read-only against Slack. The only things written are local state (last-checked timestamp, one marker per started PR), the orchestrator sessions, and messages to them.

## State

`~/.local/state/cvr-pr-review-watch/last-check` holds one epoch-seconds timestamp, e.g. `1760956200`.

- Missing file → first run: use 24 hours ago and say so in the report.
- The user can override the window: "since Monday", "last 3 days" → use that instead of the file, and still update the file afterwards.
- The user can name a PR directly ("start a review for cvr-client PR 600") → skip Slack and go to step 4 for that PR.

## Steps

1. **Read the window.** `cat ~/.local/state/cvr-pr-review-watch/last-check 2>/dev/null`. Capture `date +%s` now; this becomes the new last-check value at the end.

2. **Read the channel.** `slack_read_channel` with `channel_id: C0BBRHW14F9`, `oldest: <window>`, `limit: 100`, `response_format: detailed`. Page with the cursor until the messages are older than the window.

3. **Pick the PRs.** Drop messages posted by Jason Jeffrey (jason.jeffrey@sohonet.com): the user's own PRs are not theirs to review. In the rest, match every `github.com/sohonet/(cvr-client|cvr-client-admin)/pull/<n>` link; a post may carry several, and FE links usually sit next to BE ones that are ignored. Each distinct repo + number is one PR. Keep the poster's name, the post text and the message `ts` (the permalink is `https://sohonet.slack.com/archives/C0BBRHW14F9/p<ts without the dot>`).

4. **Start or relay**, once per PR:
   ```bash
   S=~/.local/state/cvr-pr-review-watch; f="$S/$REPO-$NUM"; mkdir -p "$S"
   [ -e "$f" ] || ~/projects/dotfiles/.claude/scripts/orchestrate-pr-review.sh "$REPO" "$NUM" "$PERMALINK" > "$f"
   ```
   The file holds the launch summary (session id and name) and is the "already started" marker, so a re-run does not start a second orchestrator. ponytail: delete the file to start it again.
   If the marker already existed, the post is a follow-up ("re-review please", "addressed the comments"): `SendMessage` to `orchestrator-pr-$REPO-$NUM` with first line `$REPO#$NUM posted in #rush-code-review by <poster>:` then the post text. If the send fails because the session is gone, say so in the report; do not restart it.

5. **Report.** One line per PR, newest first:
   ```
   ## FE PRs in #rush-code-review since Tue 21 Oct 09:30

   - cvr-client#600 · aliaksandra.zinkevich · Add new content to a Cut — orchestrator started: orchestrator-pr-cvr-client-600
   - cvr-client#598 · Tom Viner · re-review please — relayed to orchestrator-pr-cvr-client-598
   - cvr-client#593 · Jason Jeffrey — skipped, own PR
   ```
   Nothing found → "No new FE PRs in #rush-code-review since <time>".

6. **Write the timestamp** captured in step 1 to the state file (`mkdir -p` the directory first). Do this only after the report is produced so a failed run is re-checked next time.

## Notes

- Only top-level channel posts are read. A PR link that appears only inside a thread reply is not picked up. ponytail: read threads with `slack_read_thread` if that ever matters.
- The orchestrator's artifact, Telegram pings and GitHub posting are described in `scripts/orchestrate-pr-review.sh`; the page fragment it injects is `reference/review-panel.html`, checked by `reference/test_review_panel.mjs` (run it from a directory with jsdom installed).

## Scheduled runs

`launchd/com.sohonet.cvr-pr-review-watch.plist` fires `scripts/run.sh` every quarter hour; the script only does a real run on weekdays 09:00–17:30 local time, via `claude -p`. Log: `~/Library/Logs/cvr-pr-review-watch.log`.

```bash
cp launchd/com.sohonet.cvr-pr-review-watch.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.sohonet.cvr-pr-review-watch.plist   # install
launchctl bootout gui/$(id -u)/com.sohonet.cvr-pr-review-watch                                   # remove
```
