#!/usr/bin/env bash
# Builds a vendored llama.xcframework pinned to a known-good llama.cpp release.
# Pinned in the spike (.omc/research/spike-llama.md): tag b9850, which resolves to
# commit 4f31eedb0ccf546b7e8d6bb243b170f12522f54d (ggml 0.15.3) — proven to link +
# run Qwen3-0.6B with Metal from Swift. Tags are mutable, so we verify the tag still
# points at the pinned commit and check out by that commit hash (content-addressed:
# a wrong or absent hash fails loudly). Artifact is gitignored.
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-b9850}"
LLAMA_COMMIT="${LLAMA_COMMIT:-4f31eedb0ccf546b7e8d6bb243b170f12522f54d}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${REPO_ROOT}/.build/llama-src"
DEST="${REPO_ROOT}/Frameworks"

if [ -d "${DEST}/llama.xcframework" ]; then
  echo "llama.xcframework already present at ${DEST} — delete it to rebuild."
  exit 0
fi

rm -rf "${WORK}"
git clone --depth 1 --branch "${LLAMA_TAG}" https://github.com/ggml-org/llama.cpp "${WORK}"
ACTUAL_COMMIT="$(git -C "${WORK}" rev-parse HEAD)"
if [ "${ACTUAL_COMMIT}" != "${LLAMA_COMMIT}" ]; then
  echo "ERROR: tag ${LLAMA_TAG} resolved to ${ACTUAL_COMMIT}, expected pinned ${LLAMA_COMMIT}." >&2
  echo "Upstream may have moved the tag. Refusing to build an unverified source tree." >&2
  exit 1
fi
# Content-addressed checkout: fails loudly if the pinned commit is absent from the clone.
git -C "${WORK}" checkout --quiet "${LLAMA_COMMIT}" \
  || { echo "ERROR: pinned commit ${LLAMA_COMMIT} not found in clone of ${LLAMA_TAG}." >&2; exit 1; }
echo "Verified llama.cpp at pinned commit ${LLAMA_COMMIT} (tag ${LLAMA_TAG})."
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
