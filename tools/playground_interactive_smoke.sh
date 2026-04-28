#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p build/bin build/reports build/cache
ponyc src/boonpony -o build/bin

build/bin/boonpony verify-pty --all --report build/reports/verify-pty.json

echo "interactive playground proof: build/reports/verify-pty.json"
echo "manual/playground transcript: build/cache/pty-playground.out"
