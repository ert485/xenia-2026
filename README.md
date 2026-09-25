# xenia-2026: Co.Hack 2026 prep kit

Project-agnostic hackathon kit: an isolated AWS member account, `26.cohack.tetl.ca` with a wildcard
certificate, GitHub OIDC deploys, per-PR preview environments, a team GPU box serving an open-weight
coding model to Claude Code and OpenCode, cost alerts with a one-command shutdown, and a defaults-first
team kit for forming a team on the day.

Start with the design spec: `docs/superpowers/specs/2026-09-23-cohack-prep-kit-design.md`.

## Dev container

Open the repo in the dev container (`.devcontainer/`) for Claude Code and OpenCode pre-wired to
the team gateway, plus a default-deny egress firewall with an explicit host allow-list. The
firewall goes up in `postStartCommand`, every time the container starts. Teammate: if that step
fails, stop and run `/doctor` before doing anything else -- do not disable or work around the
firewall. Agent: if the firewall step failed, stop and run `/doctor` before continuing any task.
