---
name: notify
description: Use when the teammate types /notify <message>, or asks the agent to tell the team something in the team channel (Discord by default).
---

Agent: post one short message to the team channel as the agent (P-comms).

1. Write the message: a summary, a link to a PR or issue, an in-repo path, or a redacted error. Never environment values, tokens, transcripts, or logs with emails or IPs (P-public/agents).
2. Run the plugin's script (two levels above this skill's base directory):

   ```bash
   <plugin root>/scripts/notify.sh "<message>"
   ```

   It prefixes `[agent · <repo> · <git user.name>]` so the team can see who ran you.
3. If it refuses, tell the teammate why (the script says) and offer a redacted version. If `DISCORD_WEBHOOK_URL` is not set, pass on the script's instructions for setting it.
