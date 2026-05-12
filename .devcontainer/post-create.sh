#!/usr/bin/env bash
set -euo pipefail

# Bring host SSH keys into the container with correct ownership and permissions
# so the `vscode` user can talk to GitHub over SSH. The host `.ssh` dir is bind-
# mounted read-only at /tmp/.ssh-host (see devcontainer.json); we copy the keys
# we need into ~/.ssh and lock down perms (sshd refuses keys with loose perms).
if [ -d /tmp/.ssh-host ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  for key in /tmp/.ssh-host/id_*; do
    [ -f "$key" ] || continue
    cp "$key" "$HOME/.ssh/"
  done

  if [ -f /tmp/.ssh-host/known_hosts ]; then
    cp /tmp/.ssh-host/known_hosts "$HOME/.ssh/"
  fi

  # Private keys → 600, public keys → 644 (the .pub chmod runs after and overrides).
  chmod 600 "$HOME"/.ssh/id_* 2>/dev/null || true
  chmod 644 "$HOME"/.ssh/id_*.pub 2>/dev/null || true
  chmod 644 "$HOME/.ssh/known_hosts" 2>/dev/null || true

  # Pre-trust github.com so the first `git push` doesn't hang on a yes/no prompt.
  if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    chmod 644 "$HOME/.ssh/known_hosts"
  fi
fi

# Install uv (project uses uv.lock).
if ! command -v uv >/dev/null 2>&1; then
  pipx install uv
fi

# Sync dependencies into the out-of-tree env so the host's macOS .venv stays untouched.
# pyobjc-framework-Vision is macOS-only; on Linux uv will fail to resolve it.
# Run best-effort so the container still comes up; the user can iterate on markers.
if ! uv sync --all-groups; then
  echo
  echo "WARN: 'uv sync --all-groups' failed."
  echo "      pyobjc-framework-Vision is macOS-only — gate it with a PEP 508 marker, e.g.:"
  echo "      \"pyobjc-framework-Vision>=10.0; sys_platform == 'darwin'\""
  echo
fi

# Make `claude` skip permission prompts by default in this container.
# The container is the trust boundary; never set this on the host.
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  if ! grep -q 'alias claude=' "$rc"; then
    echo 'alias claude="claude --dangerously-skip-permissions"' >> "$rc"
  fi
done
