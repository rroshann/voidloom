#!/usr/bin/env bash
# Builds a vendored llama.xcframework pinned to a known-good llama.cpp release.
# Pinned in the spike (.omc/research/spike-llama.md): tag b9850 (commit 4f31eedb0),
# proven to link + run Qwen3-0.6B with Metal from Swift. Artifact is gitignored.
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-b9850}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${REPO_ROOT}/.build/llama-src"
DEST="${REPO_ROOT}/Frameworks"

if [ -d "${DEST}/llama.xcframework" ]; then
  echo "llama.xcframework already present at ${DEST} — delete it to rebuild."
  exit 0
fi

rm -rf "${WORK}"
git clone --depth 1 --branch "${LLAMA_TAG}" https://github.com/ggml-org/llama.cpp "${WORK}"
pushd "${WORK}" >/dev/null
# build-xcframework.sh defaults: GGML_METAL=ON, GGML_METAL_EMBED_LIBRARY=ON,
# MACOS_MIN_OS_VERSION=13.3 (compatible with Voidloom's macOS 14 floor).
./build-xcframework.sh
popd >/dev/null

mkdir -p "${DEST}"
cp -R "${WORK}/build-apple/llama.xcframework" "${DEST}/llama.xcframework"
echo "Vendored ${DEST}/llama.xcframework from llama.cpp ${LLAMA_TAG}"
echo "Header for the Cllama module map:"
find "${DEST}/llama.xcframework" -name llama.h -maxdepth 4 -print
