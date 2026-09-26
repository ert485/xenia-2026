# make check is one of only two blocking gates (P-two-gates) and must be identical locally and in CI.
# Extend the recipe at idea lock (C9); don't add a second gate.
.PHONY: check types
check:
	@if [ -f package.json ]; then npm run --if-present check; fi
	@if [ -f pyproject.toml ]; then ruff check . && mypy . && pytest -q; fi
	@if [ ! -f package.json ] && [ ! -f pyproject.toml ]; then echo "check: no project yet; wire typecheck, lint, and tests here (idea lock, C9)"; fi

# make types regenerates contract types from contracts/openapi.yaml (C13, P-contracts). contract-check.yml
# runs it and fails a PR whose src/contracts/ is stale. Versions are pinned so every machine generates
# identical files.
OPENAPI_TS := openapi-typescript@7.13.0
types:
	@if [ ! -f contracts/openapi.yaml ]; then echo "types: no contracts/openapi.yaml, nothing to generate (this repo skips contracts)"; exit 0; fi; \
	mkdir -p src/contracts; \
	if [ -f package.json ]; then npx --yes $(OPENAPI_TS) contracts/openapi.yaml -o src/contracts/openapi.d.ts; fi; \
	if [ -f pyproject.toml ]; then datamodel-codegen --input contracts/openapi.yaml --input-file-type openapi --output src/contracts/models.py --output-model-type pydantic_v2.BaseModel --disable-timestamp; fi
