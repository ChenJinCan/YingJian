#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

list_gates() {
  cat <<'EOF'
1. source hygiene
2. Flutter static and unit tests
3. iOS native tests
4. iOS real-fixture reshape contours
5. iOS runtime journey
6. normal iOS app startup
7. image corpus contracts
8. composition engineering corpus
9. basic tone engineering corpus
10. basic editing engineering corpus
11. quality enhancement engineering corpus
12. semantic editing engineering corpus
13. group consistency engineering corpus
14. portrait engineering corpus
15. portrait engineering diagnostic tools
16. portrait review structure
17. six-capability portrait quality contract
18. iOS device evidence contract
19. release contract
EOF
}

if [ "${1:-}" = "--list" ]; then
  list_gates
  exit 0
fi

automatic_only=false
if [ "${1:-}" = "--automatic" ]; then
  automatic_only=true
  shift
fi

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/run_ios_mvp_engineering_gate.sh [--automatic] IOS_SIMULATOR_ID" >&2
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
if [ "$automatic_only" = false ]; then
  require_file "$device_manifest"
fi

if ! xcrun simctl list devices booted | grep -F "($simulator_id) (Booted)" >/dev/null; then
  echo "iOS Simulator $simulator_id must already be booted" >&2
  exit 65
fi

portrait_workspace=$(mktemp -d "$repo_root/.quality/ios-mvp-portrait-gate.XXXXXX")
portrait_output="$portrait_workspace/output"
composition_workspace=$(mktemp -d "$repo_root/.quality/ios-mvp-composition-gate.XXXXXX")
composition_output="$composition_workspace/output"
tone_workspace=$(mktemp -d "$repo_root/.quality/ios-mvp-tone-gate.XXXXXX")
tone_output="$tone_workspace/output"
basic_workspace=$(mktemp -d "$repo_root/.quality/ios-mvp-basic-gate.XXXXXX")
basic_output="$basic_workspace/output"
quality_workspace=$(mktemp -d "$repo_root/.quality/ios-mvp-quality-gate.XXXXXX")
quality_output="$quality_workspace/output"
semantic_workspace=$(mktemp -d "$repo_root/.quality/ios-mvp-semantic-gate.XXXXXX")
semantic_output="$semantic_workspace/output"
group_workspace=$(mktemp -d "$repo_root/.quality/ios-mvp-group-gate.XXXXXX")
group_output="$group_workspace/output"
flutter_config_root=$(mktemp -d "${TMPDIR:-/tmp}/yingjian-ios-flutter-config.XXXXXX")
cleanup() {
  if [ -d "$portrait_workspace" ]; then
    find "$portrait_workspace" -depth -delete
  fi
  if [ -d "$composition_workspace" ]; then
    find "$composition_workspace" -depth -delete
  fi
  if [ -d "$tone_workspace" ]; then
    find "$tone_workspace" -depth -delete
  fi
  if [ -d "$basic_workspace" ]; then
    find "$basic_workspace" -depth -delete
  fi
  if [ -d "$flutter_config_root" ]; then
    find "$flutter_config_root" -depth -delete
  fi
  if [ -d "$quality_workspace" ]; then
    find "$quality_workspace" -depth -delete
  fi
  if [ -d "$semantic_workspace" ]; then
    find "$semantic_workspace" -depth -delete
  fi
  if [ -d "$group_workspace" ]; then
    find "$group_workspace" -depth -delete
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
export XDG_CONFIG_HOME="$flutter_config_root"
flutter config --no-enable-android --enable-ios >/dev/null
flutter config --no-enable-swift-package-manager >/dev/null

run_gate "source hygiene: format" \
  dart format -o none --set-exit-if-changed lib test integration_test
run_gate "source hygiene: diff" git diff --check

run_gate "Flutter static analysis" flutter analyze
run_gate "Flutter unit and widget tests" flutter test

run_gate "restore normal iOS Flutter build configuration" \
  flutter build ios --debug --simulator --config-only
run_gate "iOS native tests" \
  xcodebuild test -quiet \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    CODE_SIGNING_ALLOWED=NO

run_gate "iOS real-fixture reshape contours" \
  ruby scripts/check_ios_reshape_fixtures.rb

xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b

runtime_runner=${YINGJIAN_IOS_RUNTIME_RUNNER:-scripts/test_ios_mvp_integration.sh}
run_gate "iOS runtime journey" "$runtime_runner" "$simulator_id"
run_gate "normal iOS app startup" scripts/test_ios_normal_startup.sh "$simulator_id"

run_gate "image corpus checker tests" ruby scripts/test_image_quality_corpus.rb
run_gate "image corpus contracts" \
  ruby scripts/check_image_quality_corpus.rb "$image_manifest"
run_gate "composition checker tests" \
  ruby scripts/test_composition_corpus.rb
run_gate "composition engineering corpus" \
  ruby scripts/run_composition_corpus.rb "$image_manifest" "$composition_output"
run_gate "basic tone checker tests" \
  ruby scripts/test_basic_tone_corpus.rb
run_gate "basic tone engineering corpus" \
  ruby scripts/run_basic_tone_corpus.rb "$image_manifest" "$tone_output"
run_gate "basic editing checker tests" \
  ruby scripts/test_basic_editing_corpus.rb
run_gate "basic editing engineering corpus" \
  ruby scripts/run_basic_editing_corpus.rb "$image_manifest" "$basic_output"
run_gate "quality enhancement checker tests" \
  ruby scripts/test_quality_enhancement_corpus.rb
run_gate "quality enhancement engineering corpus" \
  ruby scripts/run_quality_enhancement_corpus.rb "$image_manifest" "$quality_output"
run_gate "semantic editing checker tests" \
  ruby scripts/test_semantic_editing_corpus.rb
run_gate "semantic editing engineering corpus" \
  ruby scripts/run_semantic_editing_corpus.rb "$image_manifest" "$semantic_output"
run_gate "group consistency checker tests" \
  ruby scripts/test_group_consistency_corpus.rb
run_gate "group consistency engineering corpus" \
  ruby scripts/run_group_consistency_corpus.rb "$image_manifest" "$group_output"

run_gate "portrait engineering checker tests" \
  ruby scripts/test_portrait_engineering_corpus.rb
run_gate "portrait engineering corpus" \
  ruby scripts/run_portrait_engineering_corpus.rb "$portrait_manifest" "$portrait_output"
run_gate "portrait engineering diagnostic tools" \
  ruby scripts/test_portrait_engineering_diagnostic.rb

run_gate "portrait review plan tools" ruby scripts/test_portrait_review_plan_tools.rb
run_gate "portrait review structure" ruby scripts/test_blind_review_tools.rb
run_gate "six-capability portrait quality contract" \
  ruby scripts/test_portrait_core_quality_scores.rb

run_gate "iOS device evidence checker tests" ruby scripts/test_device_evidence.rb
if [ "$automatic_only" = true ]; then
  run_gate "iOS device evidence status (non-closing)" \
    ruby scripts/check_device_evidence.rb "$device_manifest" --allow-incomplete
else
  run_gate "iOS device evidence contract" \
    ruby scripts/check_device_evidence.rb "$device_manifest"
fi

run_gate "release contract tests" bash scripts/test_release_contract.sh
run_gate "release contract" ruby scripts/check_release_contract.rb validate-config

if [ "$automatic_only" = true ]; then
  printf '\niOS MVP automatic engineering gate passed. Physical-device, human-review, and delivery gates remain open.\n'
else
  printf '\niOS MVP engineering gate passed. Human review and delivery remain separate gates.\n'
fi
