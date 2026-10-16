---
name: jira-story-planner
description: Turn a Jira story into an implementation plan. Reads the ticket's acceptance criteria and linked Figma designs, checks them against CVR knowledge-base decisions, grounds every step in the current codebase, and asks JJ (after a Telegram ping) whenever the ticket is ambiguous. Read-only; never edits code. Use when the user says "plan CVR-1234", "how should I approach this ticket", "read the ACs and make a plan", "what does this story need", or pastes a Jira key/URL and asks what to do.
---

# Jira Story Planner

Turn Jira story `$ARGUMENTS` into a plan another engineer can execute without re-reading the ticket. This skill writes no code. It reads the ticket, the designs, the decisions, and the codebase, and produces a plan. If `$ARGUMENTS` is empty, ask JJ for the ticket key before anything else.

To run it in a fresh session from a terminal: `claude "/jira-story-planner CVR-1234"`.

Jira site `https://sohonet.atlassian.net`, cloudId `3e82e209-b61e-4bbc-8b4f-f004bc048a95`. If a call rejects that cloudId, call `getAccessibleAtlassianResources` and use the returned one.

## Steps

1. **Fetch the ticket.** `getJiraIssue` with `view: full` so custom fields and attachments come back. Capture: summary, description, acceptance criteria (usually a heading or bullet list in the description, sometimes a custom field named "Acceptance Criteria"), attachments, issue links, parent epic, and the last 20 comments via `executeRead` + `listJiraIssueComments`. Comments often amend the ACs; a later comment beats the description.

2. **Find designs.** Collect every `figma.com/(design|file|proto|board)/<fileKey>/...?node-id=<id>` URL from the description, comments, remote/web links (`discover` "remote links" if none in the text), and attachment names. If there are none, say so once and move on.

3. **Read the designs.** `ToolSearch "+figma"` to load the Figma tools. The node id in the URL is `1-23`; the API wants `1:23`.
   - `get_metadata` on the file/node first to see the frame tree cheaply.
   - `get_screenshot` on each frame the ACs refer to, and look at it.
   - `get_design_context` only on frames you need exact spacing, copy, states, or component names from. Load the `figma-design-to-code` skill first if it is listed. It is large; do not call it on a whole page.
   If the only Figma tool available is `authenticate`, do not try to log in. Plan from the ticket text, and put a line at the top of the plan saying Figma was not readable and the user should run the Figma MCP auth.

4. **Check decisions.** Invoke the `cvr-context-lookup` skill for the story's subject and for each AC that touches behaviour, naming, or UX. Decisions in the knowledge base and recent Slack override the ticket text and the Figma where they conflict. Record every decision you relied on with its source so the reader can check it.

5. **Ground it in code.** Work from the current working directory. For each AC, find the files it touches: components, routes, models, API handlers, existing tests. Note existing helpers and patterns to reuse so the plan does not propose re-implementing them. If the story spans CVR repos and you are not in the right one, invoke the `cvr-codebase-lookup` skill rather than guessing.

6. **Reconcile.** Where the ACs, the Figma, the decisions, and the code disagree, say so explicitly. Do not silently pick one. If a conflict or gap changes what gets built, that is a question for JJ, not a judgement call: go to "When unsure".

## When unsure

You are unsure when any of these is true: an AC can be read two ways that lead to different code; the Figma and the ACs conflict; a decision in the knowledge base contradicts the ticket; a design state the ACs need is missing from Figma; the ticket depends on something you cannot find in code. Do not guess and do not pad the plan with assumptions.

JJ may have stepped away from the terminal, so get their attention first, then ask:

1. Write the questions to `$CLAUDE_JOB_DIR/tmp/jira-story-planner-questions.txt` (or `$TMPDIR` outside a job). Plain text, under 4096 characters: first line `CVR-1234 needs your input before I can plan it`, then one numbered question per line.
2. Ping JJ on Telegram:
   ```bash
   set -a; . ~/.config/cvr-jira-updates/.env; set +a
   curl -sS -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
     --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
     --data-urlencode "text@$FILE" | jq -r '.ok'
   ```
   If the env file is missing, say so and carry on to step 3.
3. Ask with `AskUserQuestion`, up to four questions per call, multiple choice where the options are obvious, one call covering everything you have. Include the partial finding that raised each question so JJ can answer from the prompt alone.
4. Fold the answers in and continue from where you stopped. Record each answer in the plan's "Decisions applied" section with source "JJ, this session".

Ask everything you have in one go. Do not come back three times. If a later step raises a genuinely new question, one more round is fine; a third is not.

## Output

Print Markdown in this shape. Keep it tight; the reader is an engineer who will start work from it.

```
# CVR-1234 · <summary>
<ticket URL> · <status> · epic: <parent or none>

## Acceptance criteria
1. <AC verbatim or lightly tidied>
2. ...

## Designs
- <frame name> (<figma URL>): what it shows, states covered, copy to use verbatim
- Not in Figma but needed by ACs: ...

## Decisions applied
- <decision> — <KB page or Slack thread> — affects AC n / step n

## Gaps and questions
- Things the ticket or design leaves undefined, ordered by how much they block work. Empty section is fine.

## Plan
Ordered steps. Each step names the files to touch and the AC(s) it satisfies.
1. **<step>** — `path/to/file` — AC 1, 3
   - detail only where a reader would otherwise guess
2. ...

## Tests
One line per AC: the test that proves it, and where it lives (existing file or new).

## Risks
- Anything that could bite: migrations, shared components, feature flags, permissions, perf. Skip the section if there are none.
```

## Rules

- Quote ACs; do not paraphrase them into something easier.
- Copy, labels, and error text come from Figma, not from your head.
- Prefer the smallest plan that satisfies every AC. Mark anything beyond the ACs as "not required by ticket" or leave it out.
- A plan built on guesses is worse than no plan. Unsure means stop and ask, per "When unsure".
- Never transition the ticket, comment on it, or edit anything.
