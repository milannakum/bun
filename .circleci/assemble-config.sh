#!/usr/bin/env bash
# Assemble a single valid CircleCI config from modular fragments (see .circleci/README.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${ROOT}/merged-config.yml"

{
  cat "${ROOT}/parts/00-version-and-parameters.yml"
  echo ""
  cat "${ROOT}/parts/10-commands.yml"
  echo ""
  echo "jobs:"
  sed 's/^/  /' "${ROOT}/linux/build-linux-gnu.job.yml"
  echo ""
  sed 's/^/  /' "${ROOT}/macos/build-macos-arm64.job.yml"
  echo ""
  sed 's/^/  /' "${ROOT}/publish/publish-github-release.job.yml"
  echo ""
  cat "${ROOT}/workflows/bun-release.yml"
} >"${OUT}"

echo "Wrote ${OUT}"
