# Filesystem governance — example

Filesystem access in Docker Sandboxes is **not** configured inside a kit. It is
configured on the host/org via mount modes, `--clone`, and `sbx policy`
governance profiles. This file documents the intended rules for this sandbox.

> This is documentation/example only. Apply these as governance profiles or
> org filesystem rules in your own environment.

## Intended rules

### Workspace — read-only host repo, private clone

Run with `--clone` so the host repository is mounted **read-only** and the
agent works on a **private in-container clone**:

```
sbx run ghcr.io/atorizva/opencode-sbx-sandbox:latest --clone .
```

- `~/src` (and the mounted workspace) is **read-only** to the agent.
- The agent's edits land in the private clone.
- Commits are exposed to the host via the `sandbox-<name>` git remote, so a
  human reviews them as a PR before they ever touch the host tree.

### Deny secrets on the filesystem

- `~/.ssh/**` — deny read/write. SSH happens through the forwarded host agent;
  no key material belongs in the sandbox filesystem.
- Host credential stores, env files, and any `.env` / token files — deny.

### Ephemeral writes

- `/tmp`, `/home/agent` are writable within the sandbox and discarded when the
  sandbox is removed.

## How to apply

These rules are set via `sbx policy` (org-level filesystem mount rules) and by
choosing `--clone` (or a `:ro` direct mount) at `sbx run` time — not by editing
any kit descriptor in this repository.
