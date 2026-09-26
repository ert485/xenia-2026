---
name: rule-feedback
description: Use when the teammate types /rule-feedback P-<slug>, <reason>, or knowingly did something differently from one of the team's rules and wants that recorded where the team reviews it.
---

Agent: record one knowing exception to a team rule. Rule feedback is feedback on the rule, never on a person (P-ours): the pile is only used to decide, as a team, whether a rule stays, changes, or the code is brought back in line. Say that to the teammate in one sentence if they seem worried about it.

1. Normalize the line with the plugin's script (two levels above this skill's base directory):

   ```bash
   <plugin root>/scripts/rule-feedback-line.sh "<what the teammate wrote after /rule-feedback>"
   ```

   If it exits 1, show the teammate its message and the format `P-<slug>, <what you did differently and why>`. The slugs are in PRINCIPLES.md and PRINCIPLES-EXTENDED.md (for example P-two-gates, P-off-switch, P-no-clickops, P-public/commit is written as P-public with the detail in the reason).
2. Tell the teammate where it will go and show the normalized line. Continue only when they confirm.
3. If this branch has an open PR (`gh pr view --json number,body` succeeds): write the body to a temp file; if it has a line that is exactly `Rule-feedback: none`, replace that line with the new one, otherwise append the new line on its own line at column 0 (no indent, not inside a code block, so the shared regex sees it). Then `gh pr edit <number> --body-file <temp file>`.
4. If there is no PR: `gh issue create --label rule-feedback --title "Rule feedback: <slug>" --body "<the normalized line>, recorded with /rule-feedback"`.
5. Reply with the PR or issue URL. The team looks at the pile at 18:00 and at the retro.

Never include environment values, tokens, transcripts, or anyone's contact details (P-public/agents).
