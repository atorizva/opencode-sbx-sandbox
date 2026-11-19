# opencode-sbx-sandbox

A Docker image for **agent flows in a sandbox**, built with
[Docker Sandboxes](https://docs.docker.com/sandboxes/) (`sbx`). It runs
**OpenCode** (headless agent) on a **Debian** base, with **uv** (Python) and
**just** installed, and two optional mixins for **SSH commit signing** and
**SSH-GitHub authentication**. Images are published to **GitHub Container
Registry (ghcr.io)** on every new tag.

The goal: an agent environment that can *run freely without supervision*,
encapsulated in a safe space by explicit network and filesystem policy.

---

## Architecture

Docker Sandboxes v3 kits are composed from three kinds. This repo ships one of
each, published as a single runnable `kind: set`:

| Kit | Kind | Role |
|-----|------|------|
| `workload/opencode-workload` | workload | Root filesystem: Debian + OpenCode + uv + just + gh, non-root `agent` (uid 1000), `ENTRYPOINT ["opencode"]`. |
| `mixins/git-ssh-sign` | mixin | SSH **commit/tag** signing via the host's forwarded SSH agent (no keys in the sandbox). |
| `mixins/github-ssh` | mixin | SSH **authentication** to `github.com` (git push/pull over SSH). |
| `set/agent-sandbox` | set | Composes the three above into one runnable artifact. |

```
workload (Debian + OpenCode + uv + just + gh)
   + git-ssh-sign (sign: git)        + github-ssh (authenticate: git@github.com)
   ----------------------------------------------------------------------------
   = agent-sandbox (set)
```

The "base image" is just the workload Dockerfile's `FROM` line (Debian
`trixie-slim`, pinned by digest). We build it from scratch rather than
extending `docker/sandbox-templates:opencode` so the exact Debian / uv / just
versions are under our control.

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

- **OpenCode** `v1.19.6` — the agent. Runs as the workload entrypoint; the
  headless mode is `opencode run <message>`.
- **uv** `0.13.9` — the Python tool. Installed via the official installer;
  **uv manages Python per project** via `.python-version`, so no system Python
  is baked in.
- **just** `1.59.0` — installed both in the image (for the agent to use later)
  and on the host (the `Justfile` here simplifies building/publishing).
- **gh** (GitHub CLI) — for authenticated GitHub API access (also used by the
  signing mixin to cross-check keys).
- **git**, **openssh-client**, **jq**, **curl**, **bash**, CA certs.

---

## Security model

### Network policy (deny-by-default)

Each kit declares `network-policy@2` allow/deny lists. Only the following
endpoints are reachable inside the sandbox:

- **OpenCode**: `opencode.ai`, `models.dev`
- **GitHub**: `api.github.com` (GET/HEAD/POST/PATCH; PUT/DELETE denied),
  `github.com` (HTTP :443 + SSH :22), `objects.githubusercontent.com`,
  `release-assets.githubusercontent.com`, `codeload.github.com`
- **PyPI**: `pypi.org`, `files.pythonhosted.org`

Everything else is denied. Credentials are **proxied**, not exposed: the
sandbox only ever sees a sentinel env var (`OPENCODE_API_KEY`, `GH_TOKEN`); the
real value is injected into matching outbound requests by the sandbox proxy.

### SSH (no keys in the sandbox)

SSH operations use the **host's forwarded SSH agent** via `ssh-agent@1`:

- `git-ssh-sign` forwards signing (`sign: [git]`) for commit/tag signatures.
- `github-ssh` forwards authentication (`authenticate: [git@github.com]`) for
  git push/pull over SSH.

Private keys stay on the host. The agent asks the host agent to sign; it never
holds the key material itself.

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
just build           # build all kits locally (no push)
just lint            # validate descriptors (offline)
just publish         # push workload + mixins + set to ghcr.io, then sign keyless
just run             # run the sandbox locally: sbx run ./workload --kit ... --clone .
```

Publishing is also automated on `main` (→ `latest`) and tags `v*` (→ semver
tags) via [`.github/workflows/publish-kits.yml`](.github/workflows/publish-kits.yml).
Kits are signed keyless with Sigstore.

---

## License

Apache-2.0. The `git-ssh-sign` and `github-ssh` mixins are ports of Docker's
Apache-2.0 `docker/sbx-kits-contrib` kits (Copyright Docker, Inc.); see
[`NOTICE`](NOTICE).

> **Note on the Docker Sandboxes product.** The `sbx` CLI and the
> `docker/sandbox-templates` images are Docker's proprietary product, free for
> commercial use with sign-in. This repository does **not** redistribute them;
> it only defines kits that target them.
