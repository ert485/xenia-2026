# shutdown.d: the off switches

Everything that costs money while it runs gets a script here (P-off-switch). `scripts/shutdown.sh`
in the kit runs the kit's entries, then the team repo's, in file-name order; `--dry-run` shows what
each would stop. `SHUTDOWN.md` is the rendered list; CI fails a PR whose `SHUTDOWN.md` is stale.

## The policy

A PR that adds or changes something billable must either touch that repo's `shutdown.d/` or
contain the line `Shutdown: none needed because <reason>` in its body. The `shutdown-coverage`
check blocks the merge otherwise. "Billable" means the diff touches `infra/`,
`.github/workflows/deploy*`, or any compose file.

## The header

Teammate: `/shutdown-entry` writes a new entry for you. By hand, the first seven lines are:

    #!/usr/bin/env bash
    # xenia-shutdown
    # stops: <what it stops, one line, including the region>
    # added-by: <GitHub handle or first name>
    # restore: <the command that brings it back, or "not reversible">
    # cost-when-running: <rate, for example "about $1.86/hour">
    set -euo pipefail

## The rules every entry follows

1. It honours `DRY_RUN=1`: prints `would stop <ids>` and changes nothing.
2. It exits 0 when nothing is running.
3. It is safe to run twice.
4. It is numbered by tens: the kit uses 10 to 39, team entries start at 40.
