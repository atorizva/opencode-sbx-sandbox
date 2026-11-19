# opencode-sbx-sandbox

A Docker image for **agent flows in a sandbox**, built with
[Docker Sandboxes](https://docs.docker.com/sandboxes/) (`sbx`). It runs
**OpenCode** (headless agent) on Docker's **shell-docker** template (Ubuntu),
with **uv** (Python) and **just** installed, composed with Docker's published
**SSH-GitHub authentication** mixin. Images are published to **GitHub Container
Registry (ghcr.io)** on every new tag.

The goal: an agent environment that can *run freely without supervision*,
encapsulated in a safe space by explicit network and filesystem policy.

---

## Architecture

Docker Sandboxes v3 kits are composed from three kinds. This repo ships a
`workload` and a `set`; the SSH mixin is Docker's published kit:

| Kit | Kind | Role |
|-----|------|------|
| `workload/opencode-workload` | workload | Root filesystem: shell-docker (Ubuntu) + OpenCode (npm) + uv + just, non-root `agent` (uid 1000), `ENTRYPOINT ["opencode"]`. |
| `docker/sbx-kit-github-ssh` | mixin | SSH **authentication** to `github.com` (Docker's kit, public). |
| `set/agent-sandbox` | set | Composes the workload + the mixin into one runnable artifact. |

```
workload (shell-docker + OpenCode + uv + just)
   + github-ssh (authenticate: git@github.com)
   ------------------------------------------------
   = agent-sandbox (set)
```

The base image is Docker's `shell-docker` template (Ubuntu, glibc). OpenCode is
installed via npm (pinned), uv is copied from the astral-sh image (pinned), and
just is added as a pinned release binary.

---

## Why Docker Sandboxes (and not OpenShell)

An earlier sibling project, `openpy-agent-sandbox`, used **NVIDIA OpenShell**
(`openshell` CLI + Landlock `policy.yaml`). OpenShell is capable, but its
complexity was getting in the way of development.

Docker Sandboxes takes the same isolation goal and expresses it as
**composable kits** (workload + mixins + set) with a declarative v3 descriptor
format, and handles the hard parts — microVM isolation, the SSH-agent forward,
credential proxying, network policy — in the `sbx` CLI rather than in
hand-written Landlock policy.

Trade-offs to be aware of:

- **Product dependency.** `sbx` and the `docker/sandbox-templates` images are
  Docker's *proprietary* product (free for commercial use, sign-in required).
  This repo defines kits that target it; it does **not** redistribute the
  product itself.
- **Filesystem isolation is governance-level**, not in-kit. OpenShell put
  read-only/read-write rules in `policy.yaml`; here they live in host/org
  governance (mount modes, `--clone`, `sbx policy`). See
  [`governance/filesystem.example.md`](governance/filesystem.example.md).
- **Network policy is per-kit**, expressed as allow/deny lists in each
  descriptor (see Security model below).

---

## Tooling inside the image

- **OpenCode** `2.0.32` — the agent, installed via npm (`@opencode/cli`) and
  pinned to an exact version. Runs as the workload entrypoint.
- **uv** `0.13.9` — the Python tool, copied from `ghcr.io/astral-sh/uv` and
  pinned; **uv manages Python per project** via `.python-version`.
- **just** `1.59.0` — installed both in the image (for the agent to use later)
  and on the host (the `Justfile` here simplifies building/publishing).
- **gh**, **git**, **jq**, **curl**, **bash**, **node/npm** — provided by the
  shell-docker template.

---

## Security model

### Network policy (deny-by-default)

The workload declares a `network-policy@2` allow/deny list. Only the following
endpoints are reachable inside the sandbox:

- **OpenCode**: `opencode.ai`, `models.opencode.ai`, `models.dev`
- **GitHub**: `api.github.com` (GET/HEAD/POST/PATCH; PUT/DELETE denied),
  `github.com` (HTTP :443 + SSH :22), `objects.githubusercontent.com`,
  `release-assets.githubusercontent.com`, `codeload.github.com`
- **PyPI**: `pypi.org`, `files.pythonhosted.org`

Everything else is denied. Credentials are **proxied**, not exposed: the
sandbox only ever sees a sentinel env var (`OPENCODE_API_KEY`, `GH_TOKEN`); the
real value is injected into matching outbound requests by the sandbox proxy.

### SSH (no keys in the sandbox)

SSH operations use the **host's forwarded SSH agent** via `ssh-agent@1`
(provided by Docker's published `github-ssh` mixin) for
`authenticate: [git@github.com]` — git push/pull over SSH.

Private keys stay on the host; the agent never holds the key material itself.

> SSH **commit signing** is not enabled yet. It can be added later by composing
> a signing mixin (`sign: [git]`).

### Clone mode and the PR flow

Run with `--clone` so the host repo is mounted **read-only** and the agent
works on a **private in-container clone**:

```sh
sbx run ghcr.io/atorizva/opencode-sbx-sandbox:latest --clone .
```

The agent commits on its own clone; those commits are exposed to the host via
the `sandbox-<name>` git remote, so a human reviews them as a PR. Nothing the
agent does can mutate the host working tree directly.

### Filesystem governance

Filesystem access is configured at the **host/org** level (mount modes,
`--clone`, `sbx policy`), not inside a kit. The rules are documented in
[`governance/filesystem.example.md`](governance/filesystem.example.md).

---

## Build, publish, run

Requires `docker` (with `buildx`), `just`, and `sbx` (signed in) on the host.

```sh
just builder-setup   # one-time: create the buildx builder
just build           # build the workload locally (no push)
just lint            # validate the workload descriptor (offline)
just publish         # push workload + set to ghcr.io, then sign keyless
just run             # run the sandbox locally: sbx run ./workload --kit ... --clone .
```

Publishing is also automated on `main` (→ `latest`) and tags `v*` (→ semver
tags) via [`.github/workflows/publish-kits.yml`](.github/workflows/publish-kits.yml).
Only the default `GITHUB_TOKEN` is required (the `github-ssh` mixin is public).
Kits are signed keyless with Sigstore.

---

## License

Apache-2.0. This repo *defines* kits that target Docker Sandboxes; the
`github-ssh` mixin is Docker's published OCI image, referenced by registry ref
rather than copied into this repo.

> **Note on the Docker Sandboxes product.** The `sbx` CLI and the
> `docker/sandbox-templates` images are Docker's proprietary product, free for
> commercial use with sign-in. This repository does **not** redistribute them;
> it only defines kits that target them.
