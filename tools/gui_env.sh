#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$ROOT/.boon-local/gui/prefix"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$PREFIX:${CMAKE_PREFIX_PATH:-}"

if [[ $# -eq 0 ]]; then
  printf 'PKG_CONFIG_PATH=%s\n' "$PKG_CONFIG_PATH"
  printf 'LD_LIBRARY_PATH=%s\n' "$LD_LIBRARY_PATH"
  printf 'CMAKE_PREFIX_PATH=%s\n' "$CMAKE_PREFIX_PATH"
  exit 0
fi

exec "$@"
