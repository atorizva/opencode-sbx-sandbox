# Build/publish automation for opencode-sbx-sandbox kits.

set shell := ["bash", "-euc", "-o", "pipefail"]

registry := "ghcr.io/atorizva"
tag := "latest"
# "default" = the active buildx builder. Run `just builder-setup` to switch it
# to a docker-container driver for multi-arch builds.
builder := "default"

workload_ref := registry + "/opencode-workload:" + tag
set_ref := registry + "/opencode-sbx-sandbox:" + tag
githubssh_ref := "sbx/github-ssh:1.1.1"

# One-time: create and select a docker-container builder (multi-arch capable).
builder-setup:
    docker buildx create --name kit-builder --driver docker-container --bootstrap
    docker buildx use kit-builder

# Validate the workload descriptor by building it with the sandbox-kit:3
# frontend (--output type=cacheonly keeps it fast and local).
lint:
    docker buildx build --builder {{builder}} -f workload/opencode-workload.yaml -t {{workload_ref}} --output type=cacheonly workload

# Build the workload to a local OCI tarball (full build, no push).
build:
    docker buildx build --builder {{builder}} -f workload/opencode-workload.yaml -t {{workload_ref}} --output type=oci,dest=/tmp/opencode-workload.tar workload

# Push workload + set to ghcr.io, then sign the set keyless.
publish:
    docker buildx build --builder {{builder}} -f workload/opencode-workload.yaml -t {{workload_ref}} --push workload
    docker buildx build --builder {{builder}} -f set/agent-sandbox.yaml -t {{set_ref}} --build-arg KIT_REGISTRY={{registry}} --build-arg KIT_TAG={{tag}} --push set
    sbx kit sign {{set_ref}}

# Sign the published set (keyless).
sign:
    sbx kit sign {{set_ref}}

# Run the sandbox locally on the current repo (clone mode).
run:
    sbx run ./workload --kit {{githubssh_ref}} --clone .
