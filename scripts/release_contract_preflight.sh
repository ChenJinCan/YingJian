#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${1:?platform is required}"
VERSION_VALUE="${2:?version is required}"
BUILD_VALUE="${3:?build is required}"

: "${RELEASE_PUBLIC_VERSION:?read the current public store version first}"
: "${RELEASE_REMOTE_LATEST_VERSION:?read the latest uploaded marketing version first}"
: "${RELEASE_REMOTE_LATEST_BUILD:?read the highest uploaded build across all version trains first}"
: "${RELEASE_BASELINE_VERIFIED_AT:?record the store lookup as an ISO-8601 timestamp}"
: "${RELEASE_SOURCE_COMMIT:?freeze the exact pushed source commit}"

ruby "$ROOT_DIR/scripts/check_release_contract.rb" validate-config \
  --root "$ROOT_DIR"
ruby "$ROOT_DIR/scripts/check_release_contract.rb" validate-env \
  --root "$ROOT_DIR" \
  --platform "$PLATFORM"
ruby "$ROOT_DIR/scripts/check_release_contract.rb" validate-candidate \
  --root "$ROOT_DIR" \
  --platform "$PLATFORM" \
  --version "$VERSION_VALUE" \
  --build "$BUILD_VALUE" \
  --public-version "$RELEASE_PUBLIC_VERSION" \
  --remote-latest-version "$RELEASE_REMOTE_LATEST_VERSION" \
  --remote-latest-build "$RELEASE_REMOTE_LATEST_BUILD" \
  --verified-at "$RELEASE_BASELINE_VERIFIED_AT"
ruby "$ROOT_DIR/scripts/check_release_contract.rb" validate-source \
  --root "$ROOT_DIR" \
  --platform "$PLATFORM" \
  --source-commit "$RELEASE_SOURCE_COMMIT"
