#!/usr/bin/env bash
# Runs once when the dev container is created (postCreateCommand). Sets up Claude Code's user settings,
# the gateway environment for every shell, the gitleaks pre-commit hook, and runs /doctor's script.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dc="$root/.devcontainer"

# Claude Code user settings (merged into an existing file in the persisted ~/.claude volume).
mkdir -p "$HOME/.claude"
if [[ -f "$HOME/.claude/settings.json" ]]; then
  jq -s '.[0] * .[1]' "$HOME/.claude/settings.json" "$dc/settings.json" > "$HOME/.claude/settings.json.new"
  mv "$HOME/.claude/settings.json.new" "$HOME/.claude/settings.json"
else
  cp "$dc/settings.json" "$HOME/.claude/settings.json"
fi

# Gateway environment in every interactive shell: keyless ai.env, then the teammate's gitignored
# ai.local.env, then the GATEWAY_KEY Codespaces secret if set.
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  touch "$rc"
  grep -q '# xenia: gateway settings' "$rc" && continue
  cat >> "$rc" <<EOF

# xenia: gateway settings
export XENIA_ROOT="$root"
set -a; source "\$XENIA_ROOT/.devcontainer/ai.env"; [ -f "\$XENIA_ROOT/.devcontainer/ai.local.env" ] && source "\$XENIA_ROOT/.devcontainer/ai.local.env"; set +a
[ -n "\${GATEWAY_KEY:-}" ] && export ANTHROPIC_AUTH_TOKEN="\$GATEWAY_KEY"
EOF
done

# Pre-commit: gitleaks with the repo's rules (the LiteLLM sk- rule), when both exist.
if command -v gitleaks >/dev/null 2>&1 && [[ -d "$root/.git" ]]; then
  cat > "$root/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
# xenia: block commits that contain keys (P-public/commit). A false positive gets a Rule-feedback line.
cfg=()
[ -f .gitleaks.toml ] && cfg=(--config .gitleaks.toml)
exec gitleaks git --pre-commit --staged --redact "${cfg[@]}"
EOF
  chmod +x "$root/.git/hooks/pre-commit"
else
  echo "postCreate: gitleaks or .git missing, so no pre-commit hook; CI still runs gitleaks" >&2
fi

# /doctor's checks, once, now (the firewall is not up yet at create time; /doctor rechecks later).
if [[ -x "$root/plugin/scripts/doctor.sh" ]]; then
  (
    set -a
    # shellcheck disable=SC1091
    source "$dc/ai.env"
    # shellcheck disable=SC1091
    [[ -f "$dc/ai.local.env" ]] && source "$dc/ai.local.env"
    set +a
    [[ -n "${GATEWAY_KEY:-}" ]] && export ANTHROPIC_AUTH_TOKEN="$GATEWAY_KEY"
    "$root/plugin/scripts/doctor.sh"
  ) || echo "postCreate: doctor reported problems; open a terminal and run /doctor in claude" >&2
fi

# fix-round-2: CLAUDE_CODE_PLUGIN_SEED_DIR (Dockerfile) alone is not enough -- Claude Code needs the
# plugin to come from a marketplace, or it reports "No plugins installed" and no hook ever runs.
# The Dockerfile also writes /opt/xenia/plugins/.claude-plugin/marketplace.json for exactly this.
# Never fails postCreate.sh itself; documented in plugin/README.md.
if command -v claude >/dev/null 2>&1; then
  if claude plugin list 2>/dev/null | grep -q xenia-kit; then
    :
  elif claude plugin marketplace add /opt/xenia/plugins >/dev/null 2>&1 \
    && claude plugin install xenia-kit@xenia >/dev/null 2>&1; then
    echo "postCreate: installed the xenia-kit plugin from its marketplace (the seed directory was not picked up)"
  else
    echo "postCreate: WARNING: the kit plugin (team rules, Stop hook and deny hooks) is not active; run /doctor" >&2
  fi
fi
echo "postCreate: done. Teammate: open a new terminal, then run claude."
