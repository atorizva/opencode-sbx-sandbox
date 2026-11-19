# AGENTS.md — Trust boundary

This repository builds sandboxed agent images. It is a **trust boundary**:
everything here ships into a container that runs untrusted or semi-trusted
agent code. Treat it accordingly.

## Rules for agents working in this repo

- **No secrets.** Never add credentials, API keys, SSH private keys, signing
  keys, or tokens to this repo, its images, or its CI. Keys are forwarded
  into the sandbox at runtime via the host SSH agent; they are never baked
  into the image.
- **Pin versions and digests.** Every base image is pinned by digest and every
  tool (OpenCode, uv, just) is pinned to an exact version. Do not float a
  `latest` tag or an unpinned `FROM`.
- **Default-deny network.** Network access inside the sandbox is allow-listed
  per endpoint. Do not widen a policy without an explicit need, and never
  allow more than the minimum host/method surface.
- **Filesystem access is governance-level.** File isolation is configured on
  the host/org (mount modes, `--clone`, governance profiles), not inside a
  kit. Do not attempt to encode filesystem allow/deny rules in a kit.
- **Do not redistribute the Docker Sandboxes product.** The `sbx` CLI and
  `docker/sandbox-templates` images are proprietary Docker tooling (free for
  commercial use with sign-in). This repo only *defines* kits that target
  them; it does not copy or republish those binaries or images.

## Scope of a change

- `workload/` — the root filesystem + agent entrypoint (OpenCode on Debian).
- `mixins/` — overlay capabilities (SSH commit signing, SSH-GitHub auth).
- `set/` — the composed, runnable kit.
- `governance/` — documented filesystem/mount rules (documentation only).
- `Justfile`, `.github/workflows/` — build/publish automation.

Keep changes minimal and scoped to the task.
