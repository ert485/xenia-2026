<!-- Kit note (Should tier): this README ships as a template and is not proven end to end unless
docs/proofs/2026-09-25-team-repo-templates.md exists in the kit repo. Teammate: delete this comment and
replace the first heading with the product's name at idea lock. -->
# Team repo

Teammate: this repo was set up from the Co.Hack 2026 kit (https://26.cohack.tetl.ca). Everything here is
public and carries your GitHub name: no keys, no contact details, nothing personal about anyone (P-public).

## Start here

1. Read `PRINCIPLES.md` (a minute). They're everyone's rules; change any line by PR.
2. Open the repo in a Codespace or the dev container (`.devcontainer/`), add your gateway key as the
   `GATEWAY_KEY` secret or in `.devcontainer/ai.local.env`, run `/doctor`, then `claude`.
3. Push a branch and open a PR: you get a preview URL within a few minutes (`make preview-url`).
4. Merge your own PR when CI is green. `main` deploys to https://app.26.cohack.tetl.ca.

## Everyday commands

| Command | What it does |
|---|---|
| `make check` | typecheck, lint, tests: the same gate CI runs |
| `make dev` | run the app locally with compose |
| `make preview-url` | this branch's preview address |
| `make types` | regenerate contract types (only with `contracts/`) |
| `/pain <one line>` | log friction; the pain-review bot ranks it |
| `/rule-feedback P-<slug>, <reason>` | record a knowing exception to a rule |
| `/notify <message>` | post to the team channel |

## Where things are

- How we work, PR lines, shutdown policy, previews: `CONTRIBUTING.md`
- Facts and workarounds for agents: `CLAUDE.md` (and `AGENTS.md` for other clients)
- What costs money and how to stop it: `SHUTDOWN.md` and `shutdown.d/`
- Repo-specific skills: `.claude/skills/`
- The team kit pages (charter, timeline, demo script): https://26.cohack.tetl.ca
