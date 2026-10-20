#!/bin/zsh -l
# Starts an orchestrator for a Jira story and drives it to the Definition of Done.
# Prints the launch summary; the session is named orchestrator-<KEY>.
# Usage: orchestrate-ticket.sh CVR-1234
set -eu
KEY=${1:?usage: orchestrate-ticket.sh CVR-1234}
cd ~/projects/cvr-meta
exec claude --bg -n "orchestrator-$KEY" --agent orchestrator "$(cat <<PROMPT
Drive Jira story $KEY from "In Progress" until every applicable item of the Definition of Done is met or explicitly handed to JJ.

## Definition of Done (Sohonet product team)

1. All code has been written.
2. Code has been pushed to version control.
3. Code has been peer reviewed.
4. Monitoring and logging have been added to the code.
5. Code is unit tested.
6. Code passes the CI build.
7. Any new build/deployment/configuration changes are implemented, documented and communicated.
8. Story deployed to a test environment and tested there.
9. Story passed UAT from the Product Manager.
10. Release notes updated.
11. Story merged and deployed to staging and tested there.
12. Documentation (user guide, help center) and wiki updated, or the gaps known and listed.
13. Load tests done, for stories with potential performance impact.
14. The work and its outcome are documented and understood by the PO/PM ahead of the show & tell.

Not every item applies to every story. The planner decides which do; you track only those.

## Steps

1. **Plan.** Start a planner: \`claude --bg -n $KEY-planner --agent jira-story-planner "Plan $KEY. After the plan, list which Definition of Done items apply to this story and why, numbered as in the list the orchestrator holds; mark the rest 'does not apply' with one line each. Send the full plan and the list to the session named orchestrator-$KEY with SendMessage, first line done:, and stay available for a verification request later. Do not stop before sending it."\` Include the Definition of Done list in that brief. The planner is read-only, so the plan arrives in its message: save it to ~/.local/state/orchestrator/$KEY/plan.md and the applicable items, each with status \`todo\` and an owner (worker, JJ, PM), to ~/.local/state/orchestrator/$KEY/dod.md. That file is the board; update it on every change.

2. **Confirm scope with JJ.** Send JJ the plan summary and the applicable-items list (Telegram ping, then AskUserQuestion). Wait for a yes, or fold in the changes. This is the one gate before code is written.

3. **Build.** Branches follow the team's jira-git-branching-strategy skill: one story branch \`$KEY\` on staging (or the repo's default branch when it has no staging), part branches on the story branch. First create the story branch once in each repo that will have more than one coder: \`cd ~/projects/cvr-meta/<repo> && git fetch origin && git push origin origin/staging:refs/heads/$KEY\` (skip if it already exists). Then start one \`cvr-coder\` per independent part of the plan: \`claude --bg -n $KEY-<part> --agent cvr-coder "<brief>"\` run from that repo. The brief carries the ticket, the repo path, the plan path, which plan steps are its part, the branch name \`$KEY-<part>\` with base \`$KEY\`, and your session name to report to. A repo with a single part gets its one coder on the story branch \`$KEY\` itself with base staging; a story spread over several repos with one coder in each is that case in every repo. Part branches exist only in a repo that has more than one coder. The coder works test-first in its own worktree, pushes, opens a draft PR against its base and reports with evidence. Items 1, 2, 4, 5 and 6 are the coder's to satisfy and to prove in its report (test output, CI link). Do not accept "tests pass" without the output. Record each coder on the board.

4. **Verify the ACs.** When every coder has reported done, send the planner (\`$KEY-planner\`, still running) the PR URLs, branches and worktree paths and ask it to check each acceptance criterion against what was built, replying done: or blocked: with a per-AC list. Send each "not met" item back to the coder that owns that part as a follow-up; when it reports again, ask the planner to re-check only those ACs. Then run the review loop, up to five rounds:

   - Start three reviewers in parallel with the same brief (plan path, and per PR its URL, repo, branch, base and worktree): \`claude --bg -n $KEY-review-opus --agent cvr-reviewer --model claude-opus-5-5 "<brief, engine: opus>"\`, \`claude --bg -n $KEY-review-codex --agent cvr-reviewer "<brief, engine: codex>"\` and \`claude --bg -n $KEY-review-cubic --agent cvr-reviewer "<brief, engine: cubic>"\`. From round two on, message the same three sessions instead of starting new ones, naming the round and the findings sent to the coder.
   - When all three have reported, merge their lists into one: drop duplicates (same file and problem), drop anything you can see is wrong by reading the code, keep the rest ordered most severe first, numbered. Save it as ~/.local/state/orchestrator/$KEY/review-<round>.md.
   - Empty merged list: the loop is done. Otherwise send each coder the items for its PR as a follow-up, wait for every coder to report done, and start the next round. After round five, whatever remains goes to JJ as an open list; do not start a sixth.

   When the loop ends clean, tell JJ the part PRs can be merged into the story branch; you merge nothing. Then open the story PR \`$KEY\` against staging as a draft (\`gh pr create --draft --base staging\`) and mark item 3 as needing a human reviewer on it. Peer review by the team is JJ's to arrange; list it for them.

5. **Beyond the code.** Items 7 to 14 need environments, people or documents. For each applicable one, decide what a worker can do (write the release-note entry, draft the docs or wiki text, draft the show & tell summary, run the deploy per the start-release-process skill when JJ has said which environment) and what only JJ or the PM can do (UAT sign-off, staging deploy approval, communicating config changes). Workers draft; humans sign off. Record the owner on the board.

6. **Report.** When every applicable item is done or handed over, tell JJ: per item, who did it and the evidence (PR, CI run, deploy tag, doc link), plus the hand-over list with exactly what JJ or the PM still has to do. Leave the worker sessions running and name them.

## When the ticket changes

The cvr-jira-updates skill messages this session when someone else changes $KEY: a new comment, an edited description, a status move. A comment or edit that touches the ACs goes to the planner to say whether the plan changes; if it does, update the plan and board and tell the affected coders. A status move to anything other than In Progress or a question aimed at JJ goes to JJ. Everything else is a line on the board.

## Rules

- Never transition, comment on or edit the Jira ticket, and never merge, push to main or deploy to an environment, unless JJ has said so in this session.
- One question round to JJ per phase at most; batch everything you have.
- If the planner says the ticket is ambiguous and JJ has not answered within the planner's own ask, do not start build workers; wait for JJ.
PROMPT
)"
