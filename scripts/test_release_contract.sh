#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/scripts/check_release_contract.rb"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/release-contract.XXXXXX")"
trap 'rm -rf "$FIXTURE_DIR" "$FIXTURE_DIR-remote.git"' EXIT

rg -Fq 'check_firebase_setup.sh" --require-configured' \
  "$ROOT_DIR/scripts/release_contract_preflight.sh"
rg -Fq 'check_legal_setup.rb' "$ROOT_DIR/scripts/release_contract_preflight.sh"

mkdir -p "$FIXTURE_DIR/release"

cat >"$FIXTURE_DIR/release/release-policy.yaml" <<'YAML'
schema_version: 2
app:
  id: fixture
packaging:
  mode: local_only
identity:
  version_rule: reuse_testing_else_patch_public
  build_rule: global_latest_plus_one
baseline:
  max_age_minutes: 30
source:
  require_clean_worktree: true
  require_upstream_sync: true
platforms:
  ios:
    identifier: com.example.fixture
    release_ready: true
    env_file: .env.testflight
    env_example: .env.testflight.example
    required_tools:
      - flutter
    required_env:
      - ASC_KEY_ID
    build_required_env: []
    upload_required_env:
      - ASC_KEY_ID
    forbidden_env:
      - VERSION
      - BUILD_NUMBER
      - RELEASE_PUBLIC_VERSION
      - RELEASE_REMOTE_LATEST_VERSION
      - RELEASE_REMOTE_LATEST_BUILD
      - RELEASE_BASELINE_VERIFIED_AT
      - RELEASE_SOURCE_COMMIT
YAML

cat >"$FIXTURE_DIR/.env.testflight" <<'ENV'
ASC_KEY_ID=placeholder
ENV

ruby "$CHECKER" validate-config \
  --root "$FIXTURE_DIR" \
  --config "$FIXTURE_DIR/release/release-policy.yaml"
ruby "$CHECKER" validate-env \
  --root "$FIXTURE_DIR" \
  --config "$FIXTURE_DIR/release/release-policy.yaml" \
  --platform ios
ruby "$CHECKER" validate-env \
  --root "$FIXTURE_DIR" \
  --config "$FIXTURE_DIR/release/release-policy.yaml" \
  --platform ios \
  --stage build

verified_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ruby "$CHECKER" validate-candidate \
  --root "$FIXTURE_DIR" \
  --config "$FIXTURE_DIR/release/release-policy.yaml" \
  --platform ios \
  --version 1.2.14 \
  --build 112 \
  --public-version 1.2.3 \
  --remote-latest-version 1.2.14 \
  --remote-latest-build 111 \
  --verified-at "$verified_at"

ruby "$CHECKER" validate-candidate \
  --root "$FIXTURE_DIR" \
  --config "$FIXTURE_DIR/release/release-policy.yaml" \
  --platform ios \
  --version 1.2.4 \
  --build 112 \
  --public-version 1.2.3 \
  --remote-latest-version 1.2.3 \
  --remote-latest-build 111 \
  --verified-at "$verified_at"

expect_failure() {
  local expected="$1"
  shift
  local output

  if output="$("$@" 2>&1)"; then
    echo "Expected failure containing: $expected" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected failure containing '$expected', got:" >&2
    echo "$output" >&2
    exit 1
  fi
}

cat >>"$FIXTURE_DIR/.env.testflight" <<'ENV'
VERSION=1.2.14
ENV
expect_failure \
  "must not define release identity variable VERSION" \
  ruby "$CHECKER" validate-env \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios

expect_failure \
  "build 113 must equal remote latest build 111 + 1" \
  ruby "$CHECKER" validate-candidate \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --version 1.2.14 \
    --build 113 \
    --public-version 1.2.3 \
    --remote-latest-version 1.2.14 \
    --remote-latest-build 111 \
    --verified-at "$verified_at"

expect_failure \
  "version must use canonical x.y.z format without leading zeroes" \
  ruby "$CHECKER" validate-candidate \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --version 1.2.014 \
    --build 112 \
    --public-version 1.2.3 \
    --remote-latest-version 1.2.14 \
    --remote-latest-build 111 \
    --verified-at "$verified_at"

expect_failure \
  "testing version 1.2.14 must be reused; candidate version must be 1.2.14" \
  ruby "$CHECKER" validate-candidate \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --version 1.2.2 \
    --build 112 \
    --public-version 1.2.3 \
    --remote-latest-version 1.2.14 \
    --remote-latest-build 111 \
    --verified-at "$verified_at"

expect_failure \
  "public version 1.2.3 is already online; candidate version must be 1.2.4" \
  ruby "$CHECKER" validate-candidate \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --version 1.2.3 \
    --build 112 \
    --public-version 1.2.3 \
    --remote-latest-version 1.2.3 \
    --remote-latest-build 111 \
    --verified-at "$verified_at"

expect_failure \
  "remote latest version 1.2.2 is lower than public version 1.2.3" \
  ruby "$CHECKER" validate-candidate \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --version 1.2.4 \
    --build 112 \
    --public-version 1.2.3 \
    --remote-latest-version 1.2.2 \
    --remote-latest-build 111 \
    --verified-at "$verified_at"

expect_failure \
  "online baseline is older than 30 minutes" \
  ruby "$CHECKER" validate-candidate \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --version 1.2.14 \
    --build 112 \
    --public-version 1.2.3 \
    --remote-latest-version 1.2.14 \
    --remote-latest-build 111 \
    --verified-at 2000-01-01T00:00:00Z

sed -i.bak 's/release_ready: true/release_ready: false/' \
  "$FIXTURE_DIR/release/release-policy.yaml"
expect_failure \
  "ios release packaging is not ready" \
  ruby "$CHECKER" validate-candidate \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --version 1.2.14 \
    --build 112 \
    --public-version 1.2.3 \
    --remote-latest-version 1.2.14 \
    --remote-latest-build 111 \
    --verified-at "$verified_at"
mv "$FIXTURE_DIR/release/release-policy.yaml.bak" \
  "$FIXTURE_DIR/release/release-policy.yaml"

rm "$FIXTURE_DIR/.env.testflight"
ruby "$CHECKER" validate-env \
  --root "$FIXTURE_DIR" \
  --config "$FIXTURE_DIR/release/release-policy.yaml" \
  --platform ios \
  --stage build
touch "$FIXTURE_DIR/.env.testflight"
expect_failure \
  "must define required variable ASC_KEY_ID" \
  ruby "$CHECKER" validate-env \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --stage upload

git -C "$FIXTURE_DIR" init -q
git -C "$FIXTURE_DIR" config user.name "Release Contract Test"
git -C "$FIXTURE_DIR" config user.email "release-contract@example.invalid"
git -C "$FIXTURE_DIR" add .
git -C "$FIXTURE_DIR" commit -qm "test synchronized source"
git init -q --bare "$FIXTURE_DIR-remote.git"
git -C "$FIXTURE_DIR" remote add origin "$FIXTURE_DIR-remote.git"
git -C "$FIXTURE_DIR" push -qu origin HEAD:main
git -C "$FIXTURE_DIR" branch --set-upstream-to=origin/main >/dev/null
source_commit="$(git -C "$FIXTURE_DIR" rev-parse HEAD)"

ruby "$CHECKER" validate-source \
  --root "$FIXTURE_DIR" \
  --config "$FIXTURE_DIR/release/release-policy.yaml" \
  --platform ios \
  --source-commit "$source_commit"

touch "$FIXTURE_DIR/untracked-release-change"
expect_failure \
  "release worktree must be clean" \
  ruby "$CHECKER" validate-source \
    --root "$FIXTURE_DIR" \
    --config "$FIXTURE_DIR/release/release-policy.yaml" \
    --platform ios \
    --source-commit "$source_commit"

ruby "$ROOT_DIR/scripts/test_verify_ios_ipa.rb"
ruby -c "$ROOT_DIR/scripts/capture_ios_device_evidence.rb" >/dev/null
ruby "$ROOT_DIR/scripts/test_mvp_acceptance.rb"
ruby "$ROOT_DIR/scripts/test_usability_evidence.rb"
ruby "$ROOT_DIR/scripts/test_build_usability_evidence.rb"
ruby "$ROOT_DIR/scripts/test_device_evidence.rb"
ruby "$ROOT_DIR/scripts/test_ios_testflight_workflow.rb"

echo "Release contract tests passed."
