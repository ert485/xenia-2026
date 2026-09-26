---
name: example-repo-skill
description: Use when the teammate asks to run this repo's app locally, see it in a browser, or read its logs. Also the example to copy when writing a new repo skill.
---

Agent: run the app for the teammate with the repo's own targets; don't invent new commands.

1. Agent: run `make dev`. It builds and starts the compose project in the foreground; run it in the
   background if you still need the terminal.
2. Agent: if the teammate wants a browser, check for `compose.override.yml`. If it is missing, offer to create
   it with exactly:

       services:
         web:
           ports: ["3000:3000"]

   Tell the teammate this file is for local use only; the kit's deploys ignore it. Use the value of
   `APP_PORT` instead of 3000 if the repo facts table in `CLAUDE.md` says the app listens elsewhere.
3. Agent: for logs, run `docker compose logs --tail 100 web`. Summarize errors in your own words; never paste
   log lines that contain emails, IP addresses, or tokens into an issue or PR (P-public/agents).
4. Agent: to stop, run `docker compose down` (add `--volumes` only if the teammate asks to wipe local data).
5. Agent: if the same fix is needed twice, add a row to "Workarounds" in `CLAUDE.md` (P-fix-once/claude-md).

To make a new repo skill, copy this folder, rename it, and rewrite the front matter and steps for a task the
team repeats.
