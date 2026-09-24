# make check is one of only two blocking gates (P-two-gates) and must be identical locally and in CI.
# Extend the recipe at idea lock (C9); don't add a second gate.
.PHONY: check
check:
	@if [ -f package.json ]; then npm run --if-present check; fi
	@if [ -f pyproject.toml ]; then ruff check . && mypy . && pytest -q; fi
	@if [ ! -f package.json ] && [ ! -f pyproject.toml ]; then echo "check: no project yet; wire typecheck, lint, and tests here (idea lock, C9)"; fi
