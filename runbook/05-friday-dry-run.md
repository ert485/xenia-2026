# 05: Friday dry run

Status: **to do** Friday 2026-09-25.

Erik: five things before bed.

1. **Five-minute run as a fake teammate.** Onboard a throwaway plus-address with `scripts/onboard-teammate.sh`, open a Codespace on the test team repo with the key as the `GATEWAY_KEY` user secret, run `bash plugin/scripts/doctor.sh` (all `ok`), run one `claude -p` task, then `scripts/offboard-teammate.sh`. Time it: under five minutes from opening the Codespace (spec section 1, criterion 3).
2. **Fill in the about-me card**: the three commented sections of `team-kit/01-about-me.md`, then merge by PR.
3. **Name the night-shift teammate slot**: decide which three-hour block Erik covers and which one needs a teammate at idea lock (charter C8).
4. **Disable the kit's deploy workflow.** Disable the kit repo's `deploy-docker-box` workflow (`gh workflow disable deploy-docker-box.yml --repo ert485/xenia-2026`) so a kit merge on Saturday cannot redeploy the hello app over the team's app; re-enable it after the event (`gh workflow enable deploy-docker-box.yml --repo ert485/xenia-2026`).
5. **Print** with `scripts/print-kit.sh`, then the copies listed in `team-kit/print/README.md`.

Evening state before bed: examples torn down (`scripts/box.sh xenia-gateway Action=app-down`), previews removed (`scripts/box.sh xenia-preview-down Pr=all`), GPU box stopped (`scripts/gpu.sh stop`), everything else up. `scripts/status.sh` shows exactly that.
