#!/bin/zsh -l
# Starts the orchestrator for a Jira story and drives it to the Definition of Done.
# Usage: orchestrate-ticket.sh CVR-1234
set -eu
KEY=${1:?usage: orchestrate-ticket.sh CVR-1234}
cd ~/projects/cvr-meta
exec claude --bg -n orchestrator --agent orchestrator "$(cat <<PROMPT
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

1. **Plan.** Start a planner: \`claude --bg -n $KEY-planner --agent jira-story-planner "Plan $KEY. After the plan, list which Definition of Done items apply to this story and why, numbered as in the list the orchestrator holds; mark the rest 'does not apply' with one line each. Send the full plan and the list to the session named orchestrator with SendMessage, first line done:. Do not stop before sending it."\` Include the Definition of Done list in that brief. The planner is read-only, so the plan arrives in its message: save it to ~/.local/state/orchestrator/$KEY/plan.md and the applicable items, each with status \`todo\` and an owner (worker, JJ, PM), to ~/.local/state/orchestrator/$KEY/dod.md. That file is the board; update it on every change.

2. **Confirm scope with JJ.** Send JJ the plan summary and the applicable-items list (Telegram ping, then AskUserQuestion). Wait for a yes, or fold in the changes. This is the one gate before code is written.

3. **Build.** Start one worker per independent part of the plan, in the repo the plan names, each in its own worktree and branch \`$KEY-<part>\` (cvr-client worktrees live in cvr-client/.worktrees/<TICKET> and need their own npm ci). The brief tells it: the plan path, its part, TDD per JJ's global rules, add logging where the plan calls for it, push the branch, open a draft PR, and report. Items 1, 2, 4, 5 and 6 are the worker's to satisfy and to prove in its report (test output, CI link). Do not accept "tests pass" without the output.

4. **Review.** When a build worker reports done, start \`$KEY-review\` with the PR and \`/code-review high\`; have it report findings to you. Send real findings back to the build worker as a follow-up message; mark item 3 as needing a human reviewer once the automated pass is clean and the PR is marked ready. Peer review by the team is JJ's to arrange; list it for them.

5. **Beyond the code.** Items 7 to 14 need environments, people or documents. For each applicable one, decide what a worker can do (write the release-note entry, draft the docs or wiki text, draft the show & tell summary, run the deploy per the start-release-process skill when JJ has said which environment) and what only JJ or the PM can do (UAT sign-off, staging deploy approval, communicating config changes). Workers draft; humans sign off. Record the owner on the board.

6. **Report.** When every applicable item is done or handed over, tell JJ: per item, who did it and the evidence (PR, CI run, deploy tag, doc link), plus the hand-over list with exactly what JJ or the PM still has to do. Leave the worker sessions running and name them.

## Rules

- Never transition, comment on or edit the Jira ticket, and never merge, push to main or deploy to an environment, unless JJ has said so in this session.
- One question round to JJ per phase at most; batch everything you have.
- If the planner says the ticket is ambiguous and JJ has not answered within the planner's own ask, do not start build workers; wait for JJ.
PROMPT
)"
