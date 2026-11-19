# syntax=docker/dockerfile:1

FROM debian:trixie-slim@sha256:7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392

ARG OPENCODE_VERSION=1.19.6
ARG UV_VERSION=0.13.9
ARG JUST_VERSION=1.59.0

# Base tooling required by the workload contract and the mixins.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (gh) — not in Debian main; install from GitHub's apt repo.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# OpenCode (single static binary).
RUN curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
        -o /tmp/opencode.tar.gz \
    && tar -xzf /tmp/opencode.tar.gz -C /tmp \
    && install -m 0755 /tmp/opencode /usr/local/bin/opencode \
    && rm -f /tmp/opencode.tar.gz /tmp/opencode

# uv (official installer; uv + uvx to /usr/local/bin). uv manages Python per project.
RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" \
    | env UV_INSTALL_DIR=/usr/local/bin sh

# just (GitHub release binary).
RUN curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz" \
        -o /tmp/just.tar.gz \
    && tar -xzf /tmp/just.tar.gz -C /tmp just \
    && install -m 0755 /tmp/just /usr/local/bin/just \
    && rm -f /tmp/just.tar.gz /tmp/just

# Non-root agent user (uid 1000) required by the workload contract.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent

# BASH_ENV file (recommended by the workload contract).
ENV BASH_ENV=/home/agent/.bash_env
RUN touch /home/agent/.bash_env && chown agent:agent /home/agent/.bash_env

USER agent
WORKDIR /home/agent
ENTRYPOINT ["opencode"]
CMD []
