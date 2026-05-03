#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPORT="${1:-build/reports/gui-sdl-live.json}"
mkdir -p "$(dirname "$REPORT")" build/cache

if command -v cosmic-background-launch >/dev/null 2>&1; then
  exec cosmic-background-launch -- env SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}" SDL_RENDER_DRIVER="${SDL_RENDER_DRIVER:-gpu}" build/bin/boonpony gui --backend sdl3 --report "$REPORT"
fi

exec env SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}" SDL_RENDER_DRIVER="${SDL_RENDER_DRIVER:-gpu}" build/bin/boonpony gui --backend sdl3 --report "$REPORT"
