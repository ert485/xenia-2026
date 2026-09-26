# Team repo Makefile, copied from the Co.Hack 2026 kit.
# make check is one of only two blocking gates (P-two-gates) and must be identical locally and in CI.
# Extend its recipe at idea lock (C9); don't add a second gate.
SHELL := /usr/bin/env bash
PREVIEW_DOMAIN ?= box.26.cohack.tetl.ca

.PHONY: check types dev preview-url

check:
	@set -e; ran=0; \
	if [ -f package.json ]; then ran=1; \
	  npm run --if-present typecheck; npm run --if-present lint; npm run --if-present test; fi; \
	if [ -f pyproject.toml ]; then ran=1; ruff check .; mypy .; pytest -q; fi; \
	if [ "$$ran" = 0 ]; then echo "check: no project yet; wire typecheck, lint, and tests here (idea lock, C9)"; fi

# make types regenerates contract types from contracts/openapi.yaml (C13, P-contracts). contract-check.yml
# runs it and fails a PR whose src/contracts/ is stale. Versions are pinned so every machine generates
# identical files.
OPENAPI_TS := openapi-typescript@7.13.0
types:
	@if [ ! -f contracts/openapi.yaml ]; then echo "types: no contracts/openapi.yaml, nothing to generate (this repo skips contracts)"; exit 0; fi; \
	mkdir -p src/contracts; \
	if [ -f package.json ]; then npx --yes $(OPENAPI_TS) contracts/openapi.yaml -o src/contracts/openapi.d.ts; fi; \
	if [ -f pyproject.toml ]; then datamodel-codegen --input contracts/openapi.yaml --input-file-type openapi --output src/contracts/models.py --output-model-type pydantic_v2.BaseModel --disable-timestamp; fi

# make dev runs the app locally with the same compose file the kit deploys. The web service publishes no
# ports (the kit's routing convention), so to open it in a browser add a compose.override.yml with
#   services: { web: { ports: ["3000:3000"] } }
# Compose reads that file automatically; the kit's deploy and preview commands never do.
dev:
	@if [ ! -f compose.override.yml ]; then echo "dev: no compose.override.yml, so web is reachable only from other containers (see the comment above make dev)"; fi
	docker compose up --build

# make preview-url prints this branch's preview address (preview-up.yml builds it on every push to the PR).
preview-url:
	@n="$$(gh pr view --json number --jq .number 2>/dev/null)"; \
	if [ -z "$$n" ]; then echo "preview-url: no open PR for this branch; push it and open a PR first"; exit 1; fi; \
	echo "https://pr-$$n.$(PREVIEW_DOMAIN)"