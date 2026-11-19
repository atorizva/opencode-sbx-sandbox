# Build/publish automation for opencode-sbx-sandbox kits.

set shell := ["bash", "-euc", "-o", "pipefail"]

registry := "ghcr.io/atorizva"
tag := "latest"
# "default" = the active buildx builder. Run `just builder-setup` to switch it
# to a docker-container driver for multi-arch builds.
builder := "default"

workload_ref := registry + "/opencode-workload:" + tag
gitsign_ref := registry + "/git-ssh-sign:" + tag
githubssh_ref := registry + "/github-ssh:" + tag
set_ref := registry + "/opencode-sbx-sandbox:" + tag

# One-time: create and select a docker-container builder (multi-arch capable).
# After this, `--builder default` resolves to it, so lint/build/publish pick it up.
builder-setup:
    docker buildx create --name kit-builder --driver docker-container --bootstrap
    docker buildx use kit-builder

# Validate every kit descriptor + dockerfile by building it with the
# sandbox-kit:3 frontend (--output type=cacheonly keeps it fast and local).
lint:
    docker buildx build --builder {{builder}} -f workload/opencode-workload.yaml -t {{workload_ref}} --output type=cacheonly workload
    docker buildx build --builder {{builder}} -f mixins/git-ssh-sign/git-ssh-sign.yaml -t {{gitsign_ref}} --output type=cacheonly mixins/git-ssh-sign
    docker buildx build --builder {{builder}} -f mixins/github-ssh/github-ssh.yaml -t {{githubssh_ref}} --output type=cacheonly mixins/github-ssh
    # The set is pure composition; it is validated when published (its refs
    # must exist in the registry first).

# Build the publishable kits to local OCI tarballs (full build, no push).
build:
    docker buildx build --builder {{builder}} -f workload/opencode-workload.yaml -t {{workload_ref}} --output type=oci,dest=/tmp/opencode-workload.tar workload
    docker buildx build --builder {{builder}} -f mixins/git-ssh-sign/git-ssh-sign.yaml -t {{gitsign_ref}} --output type=oci,dest=/tmp/git-ssh-sign.tar mixins/git-ssh-sign
    docker buildx build --builder {{builder}} -f mixins/github-ssh/github-ssh.yaml -t {{githubssh_ref}} --output type=oci,dest=/tmp/github-ssh.tar mixins/github-ssh

# Push workload + mixins + set to ghcr.io, then sign the set keyless.
publish:
    docker buildx build --builder {{builder}} -f workload/opencode-workload.yaml -t {{workload_ref}} --push workload
    docker buildx build --builder {{builder}} -f mixins/git-ssh-sign/git-ssh-sign.yaml -t {{gitsign_ref}} --push mixins/git-ssh-sign
    docker buildx build --builder {{builder}} -f mixins/github-ssh/github-ssh.yaml -t {{githubssh_ref}} --push mixins/github-ssh
    docker buildx build --builder {{builder}} -f set/agent-sandbox.yaml -t {{set_ref}} --build-arg KIT_REGISTRY={{registry}} --build-arg KIT_TAG={{tag}} --push set
    sbx kit sign {{set_ref}}

# Sign the published set (keyless).
sign:
    sbx kit sign {{set_ref}}

# Run the sandbox locally on the current repo (clone mode).
run:
    sbx run ./workload --kit ./mixins/git-ssh-sign --kit ./mixins/github-ssh --clone .
