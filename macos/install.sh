#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

mkdir -p "$INSTALL_DIR"
install -m 755 "$ROOT_DIR/codex-proxy" "$INSTALL_DIR/codex-proxy"

printf 'Installed: %s/codex-proxy\n' "$INSTALL_DIR"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) printf 'Add this directory to PATH, or run the command by its full path.\n' ;;
esac
