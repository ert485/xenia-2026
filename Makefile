SHELL := /usr/bin/env bash
STACKS := org platform recipes/docker-box recipes/gpu-box recipes/static-site recipes/dynamodb-table examples/kit-site
SCRIPTS := $(shell find scripts shutdown.d plugin infra templates .devcontainer -type f -name '*.sh' 2>/dev/null)
WORKFLOWS := $(wildcard templates/workflows/*.yml) $(wildcard .github/workflows/*.yml)

.PHONY: check tools fmt validate lint test workflows leak plugin-sync-check sync-plugin sync-workflows shutdown-md shutdown-md-check

check: fmt validate lint test workflows leak plugin-sync-check shutdown-md-check
	@echo "make check: OK"

tools: ## install the local toolchain (macOS)
	brew install bats-core zizmor pinact shellcheck actionlint
	brew install --cask session-manager-plugin
	test -d .venv || python3 -m venv .venv
	.venv/bin/pip install -q 'mkdocs-material>=9.5,<10' segno

fmt:
	@if [ -d infra ]; then terraform fmt -check -recursive infra; fi

validate:
	@for s in $(STACKS); do \
	  [ -f infra/$$s/versions.tf ] || continue; \
	  echo "validate infra/$$s"; \
	  (cd infra/$$s && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; \
	done

lint:
	@if [ -n "$(SCRIPTS)" ]; then shellcheck -x $(SCRIPTS); fi
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done

test:
	bats -r tests

workflows:
	@if [ -n "$(strip $(WORKFLOWS))" ]; then actionlint $(WORKFLOWS); fi
	@if [ -n "$(strip $(WORKFLOWS))" ]; then zizmor --min-severity medium --persona regular $(WORKFLOWS); fi

leak:
	@if [ -x scripts/ci/leak-check.sh ]; then scripts/ci/leak-check.sh README.md docs team-kit runbook plugin templates site infra/examples; else echo "leak: scripts/ci/leak-check.sh not present yet (Task 2)"; fi

plugin-sync-check:
	@if [ -f team-kit/PRINCIPLES.md ]; then diff -q team-kit/PRINCIPLES.md plugin/bundled/PRINCIPLES.md || { echo "plugin/bundled/PRINCIPLES.md is stale: run make sync-plugin"; exit 1; }; fi

sync-plugin:
	mkdir -p plugin/bundled && cp team-kit/PRINCIPLES.md plugin/bundled/PRINCIPLES.md

sync-workflows: ## the kit runs its own templates; check.yml is kit-specific and not synced
	@for f in shutdown-coverage render-shutdown-md pr-review; do [ -f templates/workflows/$$f.yml ] && cp templates/workflows/$$f.yml .github/workflows/$$f.yml; done; true

shutdown-md:
	scripts/render-shutdown-md.sh > SHUTDOWN.md

shutdown-md-check:
	@if [ -x scripts/render-shutdown-md.sh ]; then scripts/render-shutdown-md.sh | diff -u SHUTDOWN.md - || { echo "SHUTDOWN.md is stale: run make shutdown-md"; exit 1; }; fi
