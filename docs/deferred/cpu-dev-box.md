# CPU dev-box recipe

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

An EC2 instance per teammate (arm64, a few vCPUs) running the kit's dev container, reached from VS Code or a
terminal over an SSM port-forward, for teammates without Docker or with a laptop too small for it.

## Why it was cut

Codespaces already covers that teammate for free on their own hours, with the same `.devcontainer/` and a
prebuilt image (spec §11). A dev box per person is another thing to secure, another place a permission-skipping
agent could hold AWS credentials, and another billable resource needing a `shutdown.d/` entry, for a case
Codespaces handles.

## What exists instead

The dev container in `.devcontainer/` (Task 8), runnable in Docker Desktop or GitHub Codespaces, with the
image prebuilt to `ghcr.io` and Codespaces prebuilds enabled, so venue Wi-Fi never gates the first session.

## How to revive

- Create `infra/recipes/dev-box/` modelled on `infra/recipes/docker-box/` (default VPC, no inbound ports, SSM
  only, IMDSv2), `t4g.xlarge` by default, one instance per entry in a `teammates` map variable, tagged
  `xenia-role=dev-box`.
- User data installs Docker and the `@devcontainers/cli`, clones the team repo, and runs `devcontainer up`.
- Add `scripts/dev-box.sh start|stop|connect <name>` (connect = `aws ssm start-session` with
  `AWS-StartPortForwardingSession` for the editor's port) and `shutdown.d/25-dev-boxes.sh` in the Appendix B
  format.
- The instance role must hold no AWS permissions beyond SSM, so agents on the box stay credential-free (D22).

Effort: 5 to 7 hours including the shutdown entry and a test with one teammate.