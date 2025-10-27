#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
RESOLVER="$SCRIPT_DIR/../lib/resolve_vendored_julia.py"

if [[ ! -f "$RESOLVER" ]]; then
  echo "Resolver script not found at $RESOLVER" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to resolve the vendored Julia binary." >&2
  exit 1
fi

PROJ_DIR="$PWD"
if [[ ! -f "$PROJ_DIR/Project.toml" && -f "$PROJ_DIR/../Project.toml" ]]; then
  PROJ_DIR="$PROJ_DIR/.."
fi

export JULIA_DEPOT_PATH="$PROJ_DIR/.julia"

JULIA_BIN_PATH="$(python3 "$RESOLVER" "$PROJ_DIR")"

exec "$JULIA_BIN_PATH" --color=yes --project="$PROJ_DIR" "$@"
