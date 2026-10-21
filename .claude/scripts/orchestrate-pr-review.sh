#!/bin/zsh -l
# Starts an orchestrator that reviews a frontend PR someone else opened and drives it
# from first findings to JJ's approval. Prints the launch summary; the session is
# named orchestrator-pr-<repo>-<number> and its workers pr-<repo>-<number>-opus and -page.
# Usage: orchestrate-pr-review.sh cvr-client 600 [slack permalink]
set -eu
USAGE='usage: orchestrate-pr-review.sh <repo> <pr-number> [slack-permalink]'
REPO=${1:?$USAGE}
NUM=${2:?$USAGE}
SLACK=${3:-}
PR=https://github.com/sohonet/$REPO/pull/$NUM
NAME=orchestrator-pr-$REPO-$NUM
WORKER=pr-$REPO-$NUM
STATE=~/.local/state/pr-review/$REPO-$NUM
PANEL=~/projects/dotfiles/.claude/skills/cvr-pr-review-watch/reference/review-panel.html
mkdir -p "$STATE"
cd ~/projects/cvr-meta/$REPO
exec claude --bg -n "$NAME" --agent orchestrator "$(cat <<PROMPT
Review $PR, a frontend PR someone else opened${SLACK:+ (asked for in #rush-code-review: $SLACK)}, and drive it from first findings to JJ's approval.

JJ is the reviewer of record. Nothing reaches GitHub except the comments JJ ticks and submits in the artifact, and the approval only when JJ presses Approve there. You post on JJ's behalf with \`gh\` (account jasonjeffrey11); you never edit the PR branch.

State dir: $STATE. Keep \`board.md\` there: artifact URL, reviewed head sha, round number, every posted comment with its GitHub id and status (open, fixed, pushback-held, replied), and the worker names. Update it on every change.

## Steps

1. **Context.** \`gh pr view $PR --json title,author,body,baseRefName,headRefName,headRefOid,state\`. If the author is jasonjeffrey11 or the PR is not open, report and stop. Find the Jira key (CVR-1234) in the title, body or branch. Cut a worktree of the head in this repo: \`git fetch origin && git worktree add .worktrees/$WORKER origin/<headRefName>\` (reuse it if it exists). Note the head sha on the board.

2. **Two workers in parallel**, both started from this directory ($PWD):
   - \`claude --bg -n $WORKER-opus --agent cvr-reviewer --model claude-opus-5-5 "<brief>"\`: engine opus; there is no story plan, so the PR description and the Jira ticket stand in for it; the PR URL, repo $REPO, branch, base branch and the worktree path; report to $NAME.
   - \`claude --bg -n $WORKER-page "<brief>"\`: read ~/projects/cvr-meta/.claude/skills/pr-visual-review/SKILL.md and follow it for $PR from the worktree path, both passes, pass 2 included. Publish the artifact. Report done: with the artifact URL, the local HTML file path, the pass 2 findings, and the numbered "Comments to raise" list (severity, anchor path:line, text). Stay running: you will be asked to edit and republish the same page later.
   Both briefs carry the report-back instruction from your agent rules.

3. **Merge.** When both have reported, make one list: drop duplicates (same file and problem), drop anything you can see is wrong by reading the code, keep the rest ordered blocker, should-fix, nit. Each item is a drafted PR comment in the page's "Comments to raise" voice: a claim plus at most one clause of evidence, anchored on a line that is inside the diff (\`gh pr diff $PR\`); when a finding sits on an unchanged line, anchor on the nearest changed line and name the real location in the text. Number them r1-1, r1-2, ... and save the list to $STATE/round-1.md.

4. **Artifact.** Send \`$WORKER-page\` the list as JSON items \`{"id","round":1,"severity","path","line","url","body"}\` (url from the skill's diff_link helper) and ask it to: keep the "Comments to raise" heading but replace that section's body with the contents of $PANEL, with the JSON in place of the placeholder inside the review-items script; republish to the same URL passing \`capabilities: {db: {}, user: {}}\`; run one \`ArtifactData\` list of \`submissions\` on it; report the URL. Then, with ArtifactData on that URL, set \`review/state\` to \`{"message": "Round 1: <n> comments drafted. Tick the ones to send, edit the text if you like, then submit."}\`. Ping JJ on Telegram the way your agent rules describe, text: "PR review ready: $PR\\n<artifact URL>". Put the URL on the board.

5. **Poll.** Schedule a check every 10 minutes with the loop skill: \`/loop 10m Run the pr-review check for $PR from step 5 of your brief\`. Each check, in this order:
   a. \`ArtifactData get review/approval\`. If it exists: \`gh pr review $PR --approve\`, set \`review/state\` message to "Approved <time>", stop the loop, and finish (step 6).
   b. \`ArtifactData get submissions/round-<current round>\`. If it exists and the board does not show it posted: post it. Items with \`reply_to\` null go in one review: \`gh api repos/sohonet/$REPO/pulls/$NUM/reviews --input <json>\` with \`event: "COMMENT"\`, \`commit_id: <head sha>\` and \`comments: [{path, line, side: "RIGHT", body}]\`. If GitHub rejects a line (422), post that comment inside the review body instead, prefixed with its path:line, and note it on the board. Items with \`reply_to\` go to \`gh api repos/sohonet/$REPO/pulls/$NUM/comments/<reply_to>/replies -f body=...\`. Post the text exactly as submitted. Record every posted comment id on the board, mark the round posted, set the state message to "Posted <n> comments <time>. Watching for the author's replies and pushes."
   c. Only once round 1 is posted: look for what the author did since the last check. New head sha (\`gh pr view --json headRefOid\`); new review comments (\`gh api repos/sohonet/$REPO/pulls/$NUM/comments\`) and issue comments (\`gh api repos/sohonet/$REPO/issues/$NUM/comments\`) by anyone but jasonjeffrey11 since the last check.
      - New commits: message \`$WORKER-opus\` with the posted comments and ask it to re-review the current head (fetch and move the worktree first) and report which are fixed, which remain, and anything new.
      - A reply on one of your comments: read the thread and the code. If the pushback holds, mark the comment pushback-held on the board, no reply needed. If it does not hold, or a change is still needed, or the author asked a question, draft a reply item \`{"id": "r<round>-<k>", "round": <next round>, "severity": <as the original>, "path", "line", "url", "reply_to": <their comment id>, "context": <their reply text>, "body": <your reply>}\`.
      - Build the next round from the reply drafts plus any new findings from the re-review as fresh comments. If it has items: send them to \`$WORKER-page\` to append to the review-items JSON and republish (same URL, same capabilities), set the state message to "Round <n>: the author replied / pushed <short sha>. <k> drafts to send.", ping Telegram with the URL, bump the round on the board. If it is empty and every posted comment is fixed or pushback-held: set the state message to "All comments addressed at <short sha>. Ready to approve.", ping Telegram once, and keep polling for the approval.
   d. If \`gh pr view --json state\` is no longer OPEN: stop the loop and finish.

6. **Finish.** Report to JJ: what was posted (ids), what the author changed, what was approved, the artifact URL, the worker names left running. End with \`result:\` on its own line.

## Rules

- Never post, reply or approve on GitHub from anything other than a submission or approval read from the artifact database. Never reword a submitted comment.
- Reuse \`$WORKER-opus\` and \`$WORKER-page\` for every round; do not start fresh workers.
- The cvr-pr-review-watch skill may message this session when someone posts about this PR in #rush-code-review again (for example "re-review please"): treat it as a poll trigger and run the step 5 check at once.
- Ask JJ only for things that are theirs: a comment you cannot anchor anywhere in the diff, or a worker that failed twice. Batch the questions.
PROMPT
)"
