---
name: cvr-jira-updates
description: Check the Jira CVR project for tickets assigned to me and report what changed since the last check (status/field changes, new comments, new assignments). Use when the user says "any jira updates", "what's changed on my tickets", "check my CVR tickets", "jira changes since yesterday", "anything new on my board", or asks for a Jira catch-up. Read-only against Jira; keeps a last-checked timestamp locally.
---

# CVR Jira Updates

Reports changes to CVR tickets assigned to the current user since the last time this skill ran.
Read-only against Jira. The only thing written is a local last-checked timestamp.

Site: `https://sohonet.atlassian.net` (cloudId `3e82e209-b61e-4bbc-8b4f-f004bc048a95`). If a call rejects that cloudId, call `getAccessibleAtlassianResources` and use the returned one.

## State

`~/.local/state/cvr-jira-updates/last-check` holds one ISO-8601 timestamp with offset, e.g. `2026-10-15T09:30:00+01:00`.

- Missing file → first run: use 24 hours ago and say so in the report.
- The user can override the window: "since Monday", "last 3 days" → use that instead of the file, and still update the file afterwards.

## Steps

1. **Read the window.** `cat ~/.local/state/cvr-jira-updates/last-check 2>/dev/null`. Capture the current time now with `date -Iseconds`; this becomes the new last-check value at the end.

2. **Find touched tickets.** `searchJiraIssuesUsingJql` with:
   ```
   project = CVR AND assignee = currentUser() AND updated >= "<YYYY-MM-DD HH:mm>" ORDER BY updated DESC
   ```
   JQL takes the timestamp as `YYYY-MM-DD HH:mm` in the user's Jira timezone, so pass the first 16 chars of the stored value with `T` replaced by a space. Fields: `summary, status, priority`. Page until `isLast`.
   Zero results → report "No changes on your CVR tickets since <time>", write the timestamp, stop.

3. **For each ticket, gather what changed.** Both calls go through `executeRead`:
   - `listJiraIssueChangelogs` — probe with `maxResults: 1` to read `total`, then request `startAt = max(0, total - 20)`, `maxResults: 20`. Keep entries with `created` later than the window. If the oldest kept entry is the first in the page and still inside the window, page backwards once more.
   - `listJiraIssueComments` — `orderBy: "-created"`, `maxResults: 20`. Keep comments with `created` later than the window.
   Run the calls for all tickets in parallel.

4. **Filter.** Drop changelog entries and comments authored by the current user (`atlassianUserInfo` → accountId). The user knows what they did; the report is about everyone else. If the user asks to include their own changes, keep them.
   Ignore `Rank` field changes. Everything else counts: status, assignee, priority, sprint, labels, description, fix version, attachments, links.
   A ticket with nothing left after filtering is still listed in a one-line "touched but only by you / rank" footer so the JQL hit is explained.

5. **Report.** Group by ticket, newest first. Format:

   ```
   ## CVR updates since Wed 15 Oct 09:30

   ### CVR-1154 · Capture and sync offline review progress · In Progress
   https://sohonet.atlassian.net/browse/CVR-1154
   - **Status** Ready for Dev → In Progress — Kerri Varner, Thu 16 Oct 10:12
   - **Comment** Kerri Varner, Thu 16 Oct 10:15: "Can you confirm the end screen copy before…" (first ~200 chars, then …)
   - **Assigned to you** — Kerri Varner, Thu 16 Oct 10:11   ← call this out first when present

   Touched only by you: CVR-1052, CVR-1249
   ```
   Flag at the top, before the per-ticket list, anything that needs the user's action: newly assigned tickets, comments that @mention them or end in a question, transitions into "Ready for QA"/"Blocked".

6. **Write the timestamp** captured in step 1 to the state file (`mkdir -p` the directory first). Do this only after the report is produced so a failed run is re-checked next time.

## Notes

- Tickets unassigned *from* the user since the last check won't appear: the JQL only matches current assignee. ponytail: add a `assignee WAS currentUser()` clause if that ever matters.
- Changelog `created` values carry a UTC offset; compare as instants, not strings.
