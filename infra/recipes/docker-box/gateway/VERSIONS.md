# Gateway image pins

| Image | Tag | Digest | Pinned |
|---|---|---|---|
| `ghcr.io/berriai/litellm` | `v1.102.1` | `sha256:87f34979b9f8cb274fac90ca8a4fdda07d8480de22755562a26adeb95ce20d02` | 2026-09-24 |
| `caddy` (builder) | `2.10-builder` | `sha256:01668408cc26e2e00c9d067c30cb43b2ba14ad1f2808beda55503cb2a31f59dc` | 2026-09-24 |
| `caddy` | `2.10` | `sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb` | 2026-09-24 |
| `postgres` | `16` | `sha256:1a6ab3f5345eb6dbe04a1349529caabdb0ab09293a09590fad07b2246bfa4b54` | 2026-09-24 |

Caddy is built with `github.com/caddy-dns/route53@v1.6.2`. The Docker box installs Compose `v2.39.2` and buildx `v0.37.1` (user-data).

## Tag deviation

The brief called for `ghcr.io/berriai/litellm:main-v1.102.1`. That tag does not exist in the
registry: paging through `ghcr.io/v2/berriai/litellm/tags/list` turned up `1.102.1` and `v1.102.1`
but nothing prefixed `main-`, and no `-stable` suffixed tags exist for this repository at all (the
brief's fallback naming). `v1.102.1` is the plain release tag for that version, so `compose.yml` and
this table pin `v1.102.1` by digest instead of `main-v1.102.1`.

## Why digests

In March 2026 a malicious LiteLLM release reached PyPI. A tag can be moved to new content; a digest
cannot. The gateway holds every teammate's key and the Bedrock path, so it only ever runs an image
someone looked at.

## How to update an image

1. Read the release notes of the new version.
2. `docker buildx imagetools inspect <image>:<tag> --format '{{json .Manifest.Digest}}'`
3. Change the tag and digest in `compose.yml` or `caddy.Dockerfile` and in the table above.
4. Open a PR (the diff touches a compose file, so it needs a `Shutdown:` line); after merge run
   `scripts/box.sh xenia-gateway Action=update`, then `curl -sS https://llm.26.cohack.tetl.ca/health/readiness`.

## Config notes

- Bedrock deployment budget: `max_budget: 25` and `budget_duration: 7d` sit under the Bedrock
  deployment's `litellm_params`. If LiteLLM rejects them there, move them to
  `litellm_settings.max_budget` and `litellm_settings.budget_duration` and record the change here.
  The AWS budget `xenia-bedrock` alerts either way.
