#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

list_gates() {
  cat <<'EOF'
1. source hygiene
2. Flutter static and unit tests
3. iOS native tests
4. iOS runtime journey
5. image corpus contracts
6. portrait engineering corpus
7. portrait review structure
8. iOS device evidence contract
9. release contract
EOF
}

if [ "${1:-}" = "--list" ]; then
  list_gates
  exit 0
fi

if [ "$#" -ne 1 ]; then
  echo "usage: IOS_SIMULATOR_ID=<booted simulator> scripts/run_ios_mvp_engineering_gate.sh \"\$IOS_SIMULATOR_ID\"" >&2
  exit 64
fi

simulator_id=$1
image_manifest=${YINGJIAN_IMAGE_CORPUS_MANIFEST:-$repo_root/.quality/corpus-manifest.local.yaml}
portrait_manifest=${YINGJIAN_PORTRAIT_CORPUS_MANIFEST:-$repo_root/.quality/portrait-corpus-manifest.local.yaml}
device_manifest=${YINGJIAN_IOS_DEVICE_EVIDENCE:-$repo_root/.quality/device-evidence/ios-mvp.yaml}

require_file() {
  if [ ! -f "$1" ]; then
    echo "iOS MVP engineering gate input is missing: $1" >&2
    exit 66
  fi
}

require_file "$image_manifest"
require_file "$portrait_manifest"
require_file "$device_manifest"

if ! xcrun simctl list devices booted | grep -F "($simulator_id) (Booted)" >/dev/null; then
  echo "iOS Simulator $simulator_id must already be booted" >&2
  exit 65
fi

portrait_output=$(mktemp -d "$repo_root/.quality/ios-mvp-portrait-gate.XXXXXX")
cleanup() {
  if [ -d "$portrait_output" ]; then
    rm -rf -- "$portrait_output"
  fi
}
trap cleanup EXIT HUP INT TERM

run_gate() {
  gate_name=$1
  shift
  printf '\n== %s ==\n' "$gate_name"
  "$@"
}

cd "$repo_root"

run_gate "source hygiene: format" \
  dart format -o none --set-exit-if-changed lib test integration_test
run_gate "source hygiene: diff" git diff --check

run_gate "Flutter static analysis" flutter analyze
run_gate "Flutter unit and widget tests" flutter test

run_gate "iOS native tests" \
  xcodebuild test \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    CODE_SIGNING_ALLOWED=NO

run_gate "iOS runtime journey" scripts/test_ios_mvp_integration.sh "$simulator_id"

run_gate "image corpus checker tests" ruby scripts/test_image_quality_corpus.rb
run_gate "image corpus contracts" \
  ruby scripts/check_image_quality_corpus.rb "$image_manifest"

run_gate "portrait engineering checker tests" \
  ruby scripts/test_portrait_engineering_corpus.rb
run_gate "portrait engineering corpus" \
  ruby scripts/run_portrait_engineering_corpus.rb "$portrait_manifest" "$portrait_output"

run_gate "portrait review plan tools" ruby scripts/test_portrait_review_plan_tools.rb
run_gate "portrait review structure" ruby scripts/test_blind_review_tools.rb

run_gate "iOS device evidence checker tests" ruby scripts/test_device_evidence.rb
run_gate "iOS device evidence contract" \
  ruby scripts/check_device_evidence.rb "$device_manifest"

run_gate "release contract tests" bash scripts/test_release_contract.sh
run_gate "release contract" ruby scripts/check_release_contract.rb validate-config

printf '\niOS MVP engineering gate passed. Human review and delivery remain separate gates.\n'
