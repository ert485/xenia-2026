---
name: shutdown-entry
description: Use when the teammate types /shutdown-entry, or adds or changes something that costs money (an instance, a managed service, a scheduled job) and needs its off switch in shutdown.d/.
---

Agent: scaffold the off switch for something billable (P-off-switch).

1. Ask the teammate for, or propose and get confirmed: a short name (lowercase, dashes), what it stops (one line), the exact command that stops it and succeeds when it is already stopped, the restore command (or `not reversible`), and the cost while running (for example `about $0.10/hour`).
2. Run the plugin's script from the repo root (two levels above this skill's base directory):

   ```bash
   <plugin root>/scripts/shutdown-entry.sh <name> "<what it stops>" "<restore command>" "<cost>" "<stop command>"
   ```

3. Run the new entry once with `DRY_RUN=1` and show the teammate the output.
4. Tell the teammate to commit it in the same PR as the billable change. With the entry in the diff, the PR needs no `Shutdown: none needed because ...` line; `shutdown-coverage` passes.
