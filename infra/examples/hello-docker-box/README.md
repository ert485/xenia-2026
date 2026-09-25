# hello-docker-box

The kit's proof that a merge to `main` reaches `https://app.26.cohack.tetl.ca` in under five minutes.
The kit repo's `APP_DIR` variable points here, so `deploy-docker-box.yml` builds this folder.

**The kit repo's own deploy of this example must be disabled before the team's app takes over
`app.` (Friday evening, runbook 05)** — otherwise the next merge to the kit's `main` redeploys this
example over the team's app.

Teammate: your own repo follows the same shape. Keep a service named `web` that listens on
`APP_PORT` (3000 by default, read on the box from `/etc/xenia.env`, not from your repo's `APP_PORT`
variable), use `image: ${IMAGE:-<name>:local}` plus `build: .`, and publish no ports. Run it locally
with `docker compose up --build` and open `http://localhost:3000` after adding a local-only
`ports: ["3000:3000"]` in a `compose.override.yml` that you don't commit.

- `/health` answers `ok` (the deploy smoke test).
- `/` answers `hello from the docker box`, the deployed commit, and the database time.

Hourly backups pick up the `db` container automatically (`app-db-1`).
