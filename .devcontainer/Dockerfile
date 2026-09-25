# xenia sandbox: Anthropic's reference Claude Code dev container (upstream-Dockerfile, commit d945a61)
# plus the kit's tools. The build context is the repository root ("context": ".." in devcontainer.json),
# so the vendored plugin/ is visible; Dockerfile.dockerignore keeps everything else out of the context.
FROM node:22-bookworm

ARG TZ=America/Regina
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=2.1.280
ARG OPENCODE_VERSION=1.18.32
ARG TERRAFORM_VERSION=1.5.7
ARG GIT_DELTA_VERSION=0.18.2
ARG GITLEAKS_VERSION=8.30.1
ARG ZSH_IN_DOCKER_VERSION=1.2.0

# Upstream tool list plus Python and certificates.
RUN apt-get update && apt-get install -y --no-install-recommends \
  less git procps sudo fzf zsh man-db unzip gnupg2 gh iptables ipset iproute2 dnsutils aggregate jq nano vim \
  python3 python3-pip python3-venv pipx ca-certificates curl wget \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Docker CLI and the compose and buildx plugins (client only; the daemon is the host's or Codespaces').
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin docker-buildx-plugin \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 (x86_64 or aarch64), Terraform (amd64 or arm64), gitleaks (x64 or arm64).
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscli.zip \
  && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscli.zip
RUN ARCH="$(dpkg --print-architecture)" \
  && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" -o /tmp/tf.zip \
  && unzip -q /tmp/tf.zip terraform -d /usr/local/bin && rm /tmp/tf.zip
RUN ARCH="$(dpkg --print-architecture | sed 's/amd64/x64/')" \
  && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${ARCH}.tar.gz" \
  | tar -xzf - -C /usr/local/bin gitleaks

# Upstream: npm global prefix, persisted history, orientation variable, workspace and config dirs.
RUN mkdir -p /usr/local/share/npm-global && chown -R node:node /usr/local/share
ARG USERNAME=node
RUN mkdir /commandhistory && touch /commandhistory/.bash_history && chown -R $USERNAME /commandhistory
ENV DEVCONTAINER=true
RUN mkdir -p /workspace /home/node/.claude && chown -R node:node /workspace /home/node/.claude
WORKDIR /workspace

RUN ARCH="$(dpkg --print-architecture)" \
  && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER node
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/home/node/.local/bin
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# The two coding agents, pinned, and the Python toolchain `make check` uses in a Python team repo.
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" "opencode-ai@${OPENCODE_VERSION}"
RUN pipx install ruff && pipx install mypy && pipx install pytest && pipx install uv \
  && uv python install 3.12

# The kit plugin, seeded at user scope (spec section 11). Kept outside ~/.claude, which is a volume.
USER root
COPY --chown=node:node plugin/ /opt/xenia/plugins/xenia-kit/
ENV CLAUDE_CODE_PLUGIN_SEED_DIR=/opt/xenia/plugins

COPY .devcontainer/init-firewall.sh .devcontainer/refresh-firewall.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/refresh-firewall.sh \
  && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/refresh-firewall.sh" > /etc/sudoers.d/node-firewall \
  && chmod 0440 /etc/sudoers.d/node-firewall
USER node
