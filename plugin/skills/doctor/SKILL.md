---
name: doctor
description: Use when the teammate types /doctor, has just opened the dev container or a Codespace, or something in their setup (gh, git, the gateway key, Docker, make check, Discord) seems broken.
---

Agent: check the teammate's setup and report it.

1. From the repo root, run the plugin's script (two levels above this skill's base directory):

   ```bash
   <plugin root>/scripts/doctor.sh
   ```

2. Show the teammate the list as printed. For every `FAIL` line, say the one next step from its hint; don't try more than that unless they ask.
3. If everything is `ok` or `warn`, say so in one line: they can start work with `claude`.

Never print the value of `ANTHROPIC_AUTH_TOKEN` or any other secret while debugging.
