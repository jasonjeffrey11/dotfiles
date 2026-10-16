---
name: jira-story-planner
description: Turn a Jira story into an implementation plan. Reads the ticket's acceptance criteria and linked Figma designs, checks them against CVR knowledge-base decisions, grounds every step in the current codebase, and asks JJ (after a Telegram ping) whenever the ticket is ambiguous. Read-only; never edits code. Use when the user says "plan CVR-1234", "how should I approach this ticket", "read the ACs and make a plan", "what does this story need", or pastes a Jira key/URL and asks what to do.
---

# Jira Story Planner

Turn the Jira story named in the request into a plan another engineer can execute without re-reading the ticket. This skill writes no code. It reads the ticket, the designs, the decisions, and the codebase, and produces a plan. If no ticket key was given, ask JJ for it before anything else.

The `jira-story-planner` agent runs this skill and carries the Jira site details, the read-only tool restrictions, the ask-JJ protocol and the planning rules. Run it in a fresh session with `claude --agent jira-story-planner "Plan CVR-1234"`.

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

6. **Reconcile.** Where the ACs, the Figma, the decisions, and the code disagree, say so explicitly. Do not silently pick one. If a conflict or gap changes what gets built, that is a question for JJ, not a judgement call: stop and ask, per the agent's "When unsure" protocol.

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
