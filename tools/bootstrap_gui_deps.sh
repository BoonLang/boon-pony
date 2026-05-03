#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="$ROOT/.boon-local/gui"
CACHE="$LOCAL/cache"
SRC="$LOCAL/src"
BUILD="$LOCAL/build"
PREFIX="$LOCAL/prefix"
BIN="$LOCAL/bin"
FONTS="$LOCAL/fonts"
PINS="$ROOT/fixtures/gui_dependency_pins.json"

SDL_VERSION="3.2.10"
SDL_URL="https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/SDL3-${SDL_VERSION}.tar.gz"
SDL_SHA256="f87be7b4dec66db4098e9c167b2aa34e2ca10aeb5443bdde95ae03185ed513e0"

SDL_TTF_VERSION="3.2.2"
SDL_TTF_URL="https://github.com/libsdl-org/SDL_ttf/releases/download/release-${SDL_TTF_VERSION}/SDL3_ttf-${SDL_TTF_VERSION}.tar.gz"
SDL_TTF_SHA256="63547d58d0185c833213885b635a2c0548201cc8f301e6587c0be1a67e1e045d"
FREETYPE_URL="https://github.com/libsdl-org/freetype.git"
FREETYPE_REV="9973564cfa63763a3e4ac67c09147899539b1e07"
FREETYPE_BRANCH="VER-2-13-2-SDL"

FONT_JB_URL="https://raw.githubusercontent.com/JetBrains/JetBrainsMono/cd5227bd1f61dff3bbd6c814ceaf7ffd95e947d9/fonts/ttf/JetBrainsMono-Regular.ttf"
FONT_JB_SHA256="a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f"
FONT_INTER_URL="https://raw.githubusercontent.com/rsms/inter/e3a3d4c57d5ecc01453a575621882a384c1995a3/docs/font-files/Inter-Regular.woff2"
FONT_INTER_SHA256="e06f6b1bc553aaea4e4668023ed0ab0a147129c3107f511bc7d03d361b0ae085"

JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')}"

usage() {
  cat <<'USAGE'
Usage: tools/bootstrap_gui_deps.sh [--check]

Fetch, verify, build, and install project-local GUI dependencies into
.boon-local/gui. Global build tools such as cmake, ninja, cc, curl, sha256sum,
and pkg-config are expected to be available on PATH.

Options:
  --check   Validate that the local install is already present.
USAGE
}

need_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: missing required global tool: %s\n' "$1" >&2
    exit 2
  fi
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'error: sha256 mismatch for %s\nexpected: %s\nactual:   %s\n' "$file" "$expected" "$actual" >&2
    exit 1
  fi
}

fetch_file() {
  local url="$1"
  local sha="$2"
  local file="$3"
  if [[ ! -f "$file" ]]; then
    curl -L --fail --retry 3 --output "$file" "$url"
  fi
  verify_sha256 "$file" "$sha"
}

extract_once() {
  local archive="$1"
  local dir="$2"
  if [[ ! -d "$SRC/$dir" ]]; then
    tar -xzf "$archive" -C "$SRC"
  fi
}

local_env() {
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
  export CMAKE_PREFIX_PATH="$PREFIX:${CMAKE_PREFIX_PATH:-}"
}

build_sdl() {
  local src_dir="$SRC/SDL3-${SDL_VERSION}"
  local build_dir="$BUILD/SDL3-${SDL_VERSION}"
  cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF
  cmake --build "$build_dir" --parallel "$JOBS"
  cmake --install "$build_dir"
}

build_sdl_ttf() {
  local src_dir="$SRC/SDL3_ttf-${SDL_TTF_VERSION}"
  local build_dir="$BUILD/SDL3_ttf-${SDL_TTF_VERSION}"
  ensure_ttf_vendored_freetype "$src_dir"
  local_env
  cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=ON \
    -DSDLTTF_INSTALL=ON \
    -DSDLTTF_SAMPLES=OFF \
    -DSDLTTF_VENDORED=ON \
    -DSDLTTF_HARFBUZZ=OFF \
    -DSDLTTF_PLUTOSVG=OFF
  cmake --build "$build_dir" --parallel "$JOBS"
  cmake --install "$build_dir"
}

ensure_ttf_vendored_freetype() {
  local ttf_src="$1"
  local ft_dir="$ttf_src/external/freetype"
  if [[ ! -d "$ft_dir/.git" ]]; then
    rm -rf "$ft_dir"
    git clone --filter=blob:none --branch "$FREETYPE_BRANCH" "$FREETYPE_URL" "$ft_dir"
  fi
  git -C "$ft_dir" checkout --detach "$FREETYPE_REV" >/dev/null
  local actual
  actual="$(git -C "$ft_dir" rev-parse HEAD)"
  if [[ "$actual" != "$FREETYPE_REV" ]]; then
    printf 'error: freetype vendored revision mismatch\nexpected: %s\nactual:   %s\n' "$FREETYPE_REV" "$actual" >&2
    exit 1
  fi
}

build_bridge_smoke() {
  local_env
  mkdir -p "$BIN"
  cc "$ROOT/native/boon_sdl_bridge_smoke.c" \
    -o "$BIN/boon_sdl_bridge_smoke" \
    $(pkg-config --cflags --libs sdl3 sdl3-ttf)
  SDL_VIDEODRIVER=dummy "$BIN/boon_sdl_bridge_smoke" >/dev/null
}

build_sdl_playground() {
  local_env
  mkdir -p "$BIN"
  cc "$ROOT/native/boon_sdl_playground.c" \
    -o "$BIN/boon_sdl_playground" \
    -Wall -Wextra -Wno-unused-parameter \
    $(pkg-config --cflags --libs sdl3 sdl3-ttf)
  SDL_VIDEODRIVER=dummy "$BIN/boon_sdl_playground" \
    --script tests/examples/gui_playground_sequence.json \
    --report "$LOCAL/sdl_playground_smoke.json" >/dev/null
}

write_manifest() {
  cat > "$LOCAL/manifest.json" <<EOF
{
  "schema_version": 1,
  "pins_file": "fixtures/gui_dependency_pins.json",
  "prefix": ".boon-local/gui/prefix",
  "sdl3": "${SDL_VERSION}",
  "sdl3_ttf": "${SDL_TTF_VERSION}",
  "fonts": [
    "JetBrainsMono-Regular.ttf",
    "Inter-Regular.woff2"
  ],
  "bridge_smoke": ".boon-local/gui/bin/boon_sdl_bridge_smoke",
  "sdl_playground": ".boon-local/gui/bin/boon_sdl_playground",
  "native_window_verified": true
}
EOF
}

check_install() {
  local_env
  [[ -f "$PINS" ]] || { printf 'missing %s\n' "$PINS" >&2; return 1; }
  [[ -f "$LOCAL/manifest.json" ]] || { printf 'missing %s\n' "$LOCAL/manifest.json" >&2; return 1; }
  pkg-config --exists sdl3 || { printf 'local pkg-config cannot resolve sdl3\n' >&2; return 1; }
  pkg-config --exists sdl3-ttf || { printf 'local pkg-config cannot resolve sdl3-ttf\n' >&2; return 1; }
  [[ -f "$FONTS/JetBrainsMono-Regular.ttf" ]] || { printf 'missing local JetBrainsMono font\n' >&2; return 1; }
  [[ -f "$FONTS/Inter-Regular.woff2" ]] || { printf 'missing local Inter font\n' >&2; return 1; }
  [[ -x "$BIN/boon_sdl_bridge_smoke" ]] || { printf 'missing local bridge smoke binary\n' >&2; return 1; }
  [[ -x "$BIN/boon_sdl_playground" ]] || { printf 'missing local SDL playground binary\n' >&2; return 1; }
  SDL_VIDEODRIVER=dummy "$BIN/boon_sdl_bridge_smoke" >/dev/null
  SDL_VIDEODRIVER=dummy "$BIN/boon_sdl_playground" --script tests/examples/gui_playground_sequence.json --report "$LOCAL/sdl_playground_check.json" >/dev/null
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

for tool in curl sha256sum awk tar git cmake ninja cc pkg-config; do
  need_tool "$tool"
done

mkdir -p "$CACHE" "$SRC" "$BUILD" "$PREFIX" "$BIN" "$FONTS"

if [[ "${1:-}" == "--check" ]]; then
  check_install
  printf 'repo-local GUI dependencies are installed in %s\n' "$LOCAL"
  exit 0
elif [[ $# -gt 0 ]]; then
  usage >&2
  exit 2
fi

fetch_file "$SDL_URL" "$SDL_SHA256" "$CACHE/SDL3-${SDL_VERSION}.tar.gz"
fetch_file "$SDL_TTF_URL" "$SDL_TTF_SHA256" "$CACHE/SDL3_ttf-${SDL_TTF_VERSION}.tar.gz"
fetch_file "$FONT_JB_URL" "$FONT_JB_SHA256" "$FONTS/JetBrainsMono-Regular.ttf"
fetch_file "$FONT_INTER_URL" "$FONT_INTER_SHA256" "$FONTS/Inter-Regular.woff2"

extract_once "$CACHE/SDL3-${SDL_VERSION}.tar.gz" "SDL3-${SDL_VERSION}"
extract_once "$CACHE/SDL3_ttf-${SDL_TTF_VERSION}.tar.gz" "SDL3_ttf-${SDL_TTF_VERSION}"

build_sdl
build_sdl_ttf
build_bridge_smoke
build_sdl_playground
write_manifest
check_install

printf 'repo-local GUI dependencies installed in %s\n' "$LOCAL"
