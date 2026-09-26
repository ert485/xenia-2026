---
name: pain
description: Use when the teammate types /pain <one line>, or says something in the kit, the tooling, or the workflow annoyed them, to log it as a friction issue that the pain-review bot ranks.
---

Agent: log one friction item as a GitHub issue in this repo. The teammate's words after `/pain` are the title; keep them short and plain.

1. Draft the issue from what the teammate said and what you saw in this session:
   - **What hurt**: one or two sentences, in the teammate's terms.
   - **How often**: once, a few times, or constantly (ask if you can't tell).
   - **Workaround**: what got them unstuck, or "none yet".
   - **Tool**: Claude Code, OpenCode, the dev container, CI, the gateway, the box, docs, or other.
2. Show the teammate the exact title and body and ask them to confirm or edit it. Everything in the repo is public (P-public/agents): a human confirms before anything is posted.
3. Only after the teammate says yes, run:

   ```bash
   gh issue create --label friction --title "<title>" --body "$(cat <<'EOF'
   **What hurt:** <...>

   **How often:** <...>

   **Workaround:** <...>

   **Tool:** <...>

   Logged with /pain.
   EOF
   )"
   ```

4. Reply with the issue URL. If `gh` says the `friction` label doesn't exist, tell the teammate the repo was not onboarded with the kit's labels and create the issue without `--label`.

Never put these in the issue: environment variable values, tokens or keys, session transcripts, log lines containing emails or IP addresses, anyone's contact details. Paraphrase errors and redact identifiers.
