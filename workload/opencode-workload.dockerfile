# OpenCode agent workload.
# Base = Docker's shell-docker template (Ubuntu, glibc). OpenCode is installed
# via npm (pinned), uv is copied from astral-sh (pinned), and just is added as
# a pinned release binary. Installs run as root; the runtime user is the
# template's non-root `agent` (uid 1000).
ARG UV_VERSION=0.13.9
ARG SHELL_DOCKER_VERSION=0.7.0
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker-${SHELL_DOCKER_VERSION}

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv-bin
FROM ${BASE_IMAGE}

ARG OPENCODE_VERSION=2.0.32
ARG JUST_VERSION=1.59.0

USER root

# uv + uvx (pinned; shell-docker ships its own uv, this pins the exact version).
COPY --from=uv-bin /uv /uvx /usr/local/bin/

# OpenCode via npm, pinned to the exact version. (Do not `corepack disable npm`
# here: in this template npm 9 is corepack-managed and disabling it removes it.)
RUN set -eux; \
    npm install -g "@opencode/cli@${OPENCODE_VERSION}" --include=optional; \
    opencode --version; \
    npm cache clean --force

# just (pinned release binary; the musl build is static and runs on glibc).
RUN curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz" \
        | tar -xz -C /usr/local/bin just \
    && just --version

USER agent
ENTRYPOINT ["opencode"]
CMD []
