# Build/publish automation for opencode-sbx-sandbox kits.

set shell := ["bash", "-euc", "-o", "pipefail"]
# Running `just` with no arguments lists recipes instead of running the first one.
set default-list

registry := "ghcr.io/atorizva"
tag := "latest"

# Builds use the active buildx builder. Run `just builder-setup` once to create
# and select a docker-container builder (needed for multi-arch builds); CI's
# docker/setup-buildx-action selects its own builder.

workload_ref := registry + "/opencode-workload:" + tag
set_ref := registry + "/opencode-sbx-sandbox:" + tag
githubssh_ref := "sbx/github-ssh:1.1.1"

# Safe to re-run: create/select a docker-container builder (multi-arch capable).
builder-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! docker buildx inspect kit-builder >/dev/null 2>&1; then
        docker buildx create --name kit-builder --driver docker-container --bootstrap
    fi
    docker buildx use kit-builder

# Validate the workload descriptor: full cache-only build (no static check mode).
validate:
    docker buildx build -f workload/opencode-workload.yaml -t {{workload_ref}} --output type=cacheonly workload

# Build the workload to a local OCI tarball (full build, no push).
build:
    docker buildx build -f workload/opencode-workload.yaml -t {{workload_ref}} --output type=oci,dest=/tmp/opencode-workload.tar workload

# Push workload + set to ghcr.io, then sign the set keyless.
publish:
    docker buildx build -f workload/opencode-workload.yaml -t {{workload_ref}} --push workload
    docker buildx build -f set/agent-sandbox.yaml -t {{set_ref}} --build-arg KIT_REGISTRY={{registry}} --build-arg KIT_TAG={{tag}} --push set
    sbx kit sign {{set_ref}}

# Sign the published set (keyless).
sign:
    sbx kit sign {{set_ref}}

# Store the OpenCode (required) and GitHub (optional) credentials in sbx.
credentials:
    #!/usr/bin/env bash
    set -euo pipefail

    read -rsp 'OpenCode API key: ' opencode_key
    echo
    if [[ -z "$opencode_key" ]]; then
        echo 'error: OpenCode API key is required' >&2
        exit 1
    fi

    # The workload declares credential service `opencode-go`, so sbx expects a
    # service secret with that name (not a custom host/env secret).
    printf '%s' "$opencode_key" | sbx secret set opencode-go --no-input --force

    read -rsp 'GitHub token (optional, Enter to skip): ' github_token
    echo
    if [[ -n "$github_token" ]]; then
        printf '%s' "$github_token" | sbx secret set github --no-input --force
    fi

    unset opencode_key github_token

    echo
    echo 'Stored secrets:'
    sbx secret ls

# Check host prerequisites for running a sandbox locally.
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    status=0
    if ! sbx diagnose; then
        status=1
    fi
    if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        printf '\nERROR: /dev/kvm is not accessible.\n' >&2
        printf '       sudo usermod -aG kvm "$USER"  # then log out/in and: sbx daemon restart\n' >&2
        status=1
    fi
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        printf '\nERROR: SSH_AUTH_SOCK is unset; git over SSH needs a host SSH agent.\n' >&2
        printf '       eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519\n' >&2
        status=1
    fi
    exit "$status"

# Run locally in clone mode (needs KVM + a host SSH agent; `just doctor` checks).
run: doctor
    sbx run ./workload --kit {{githubssh_ref}} --clone .
