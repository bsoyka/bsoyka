#!/usr/bin/env bash
# Stage the transform Lambda's deployable contents in build/staging/transform.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$root_dir/lambda/transform"
stage_dir="$root_dir/build/staging/transform"

rm -rf "$stage_dir"
mkdir -p "$stage_dir"

cp "$src_dir/index.mjs" "$src_dir/package.json" "$stage_dir/"

# sharp ships prebuilt native binaries per platform. Lambda runs arm64 Linux
# regardless of what this script runs on (e.g. an Apple Silicon Mac, which
# would otherwise resolve the darwin-arm64 build that Lambda can't load).
npm install \
    --prefix "$stage_dir" \
    --os=linux \
    --cpu=arm64 \
    --libc=glibc \
    --omit=dev \
    --no-audit \
    --no-fund

rm -f "$stage_dir/package-lock.json"
