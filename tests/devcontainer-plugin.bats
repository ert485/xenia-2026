#!/usr/bin/env bats
# Fix round 2: two load-bearing dev container findings.
#
# 1. CLAUDE_CODE_PLUGIN_SEED_DIR alone left the plugin invisible to `claude plugin list` ("No
#    plugins installed"), so no hook ever ran. The fix is a marketplace.json seeded next to the
#    plugin, plus postCreate.sh adding that marketplace and installing xenia-kit@xenia from it.
# 2. devcontainer exec / VS Code on a Mac forward LC_ALL/LANG=en_US.UTF-8, which the base image
#    lacked, breaking exact-match bats tests inside the container with a setlocale warning.
#
# Both fixes touch two copies each (.devcontainer/ and templates/devcontainer/) that must stay
# byte-identical; this file checks the content and the identity, not the built image (no docker
# here).

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "both Dockerfile copies seed a marketplace.json pointing at ./xenia-kit" {
  for f in .devcontainer/Dockerfile templates/devcontainer/Dockerfile; do
    grep -qF 'marketplace.json' "$f"
    grep -qF '"source":"./xenia-kit"' "$f"
  done
}

@test "both postCreate.sh copies install xenia-kit@xenia from the marketplace" {
  for f in .devcontainer/postCreate.sh templates/devcontainer/postCreate.sh; do
    grep -qF 'claude plugin install xenia-kit@xenia' "$f"
  done
}

@test "both postCreate.sh copies warn instead of failing when the plugin install does not work" {
  for f in .devcontainer/postCreate.sh templates/devcontainer/postCreate.sh; do
    grep -qF 'postCreate: WARNING' "$f"
  done
}

@test "both Dockerfile copies install locales and generate en_US.UTF-8" {
  for f in .devcontainer/Dockerfile templates/devcontainer/Dockerfile; do
    grep -qE '(^|[^a-z-])locales([^a-z-]|$)' "$f"
    grep -qF 'locale-gen' "$f"
    grep -qF 'en_US.UTF-8' "$f"
  done
}

@test "the Dockerfile and postCreate.sh pairs are byte-identical" {
  cmp .devcontainer/Dockerfile templates/devcontainer/Dockerfile
  cmp .devcontainer/postCreate.sh templates/devcontainer/postCreate.sh
}
