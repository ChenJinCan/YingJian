#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_OPTIONS="$ROOT_DIR/release/ExportOptions.testflight.plist"
source "$ROOT_DIR/scripts/lib/load_testflight_environment.sh"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

VERSION_VALUE="${1:-}"
BUILD_VALUE="${2:-}"
if ! [[ "$VERSION_VALUE" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "version must use canonical x.y.z format without leading zeroes" >&2
  exit 64
fi
if ! [[ "$BUILD_VALUE" =~ ^[1-9][0-9]*$ ]]; then
  echo "build must be a positive integer" >&2
  exit 64
fi

print_plan() {
  cat <<EOF
LOCAL-ONLY: build one signed iOS IPA; this command never contacts App Store Connect.
release_contract_preflight.sh ios $VERSION_VALUE $BUILD_VALUE build
flutter build ipa --release --build-name $VERSION_VALUE --build-number $BUILD_VALUE --export-options-plist release/ExportOptions.testflight.plist
Flutter runs with an isolated configuration where Android discovery is disabled. Swift Package Manager migration is disabled for this CocoaPods project.
verify_ios_ipa.rb <IPA> --bundle-id com.babycompany.yingjian --version $VERSION_VALUE --build $BUILD_VALUE --source-commit <RELEASE_SOURCE_COMMIT> --firebase-config ios/Runner/GoogleService-Info.plist
EOF
}

if [[ "$DRY_RUN" == true ]]; then
  print_plan
  exit 0
fi

cd "$ROOT_DIR"
load_testflight_environment "$ROOT_DIR"
: "${RELEASE_SOURCE_COMMIT:?freeze the exact pushed source commit before building}"
[[ -f "$EXPORT_OPTIONS" ]] || { echo "missing $EXPORT_OPTIONS" >&2; exit 66; }

echo "LOCAL-ONLY: validating iOS candidate $VERSION_VALUE ($BUILD_VALUE) at $RELEASE_SOURCE_COMMIT."
"$ROOT_DIR/scripts/release_contract_preflight.sh" ios "$VERSION_VALUE" "$BUILD_VALUE" build

ipa_directory="$ROOT_DIR/build/ios/ipa"
report_directory="$ROOT_DIR/.release-state/ios"
candidate_directory="$report_directory/artifacts/$VERSION_VALUE-$BUILD_VALUE"
report_path="$candidate_directory/artifact.json"
build_identity_path="$ROOT_DIR/assets/build/source-commit.txt"
if [[ -e "$build_identity_path" ]]; then
  echo "stale iOS build identity exists: $build_identity_path" >&2
  exit 69
fi
mkdir -p "$report_directory/artifacts" "$report_directory/preserved"
build_lock="$report_directory/build.lock"
if ! mkdir "$build_lock"; then
  echo "another iOS candidate build owns $build_lock; reconcile it before retrying" >&2
  exit 70
fi

flutter_config_root=""
cleanup_flutter_config() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ -n "$flutter_config_root" && -d "$flutter_config_root" ]]; then
    find "$flutter_config_root" -depth -delete
  fi
  if [[ -f "$build_identity_path" ]]; then
    unlink "$build_identity_path"
  fi
  if [[ -d "$build_lock" ]]; then
    rmdir "$build_lock" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup_flutter_config EXIT HUP INT TERM

if ! mkdir "$candidate_directory"; then
  echo "candidate evidence already exists; preserve or move it deliberately: $candidate_directory" >&2
  exit 68
fi
flutter_config_root=$(mktemp -d "${TMPDIR:-/tmp}/yingjian-ios-flutter-config.XXXXXX")
export XDG_CONFIG_HOME="$flutter_config_root"
printf '%s\n' "$RELEASE_SOURCE_COMMIT" > "$build_identity_path"
flutter config \
  --no-enable-android \
  --enable-ios \
  --no-enable-swift-package-manager >/dev/null

if [[ -d "$ipa_directory" ]]; then
  old_ipas=()
  while IFS= read -r -d '' old_ipa; do old_ipas+=("$old_ipa"); done < <(find "$ipa_directory" -maxdepth 1 -type f -name '*.ipa' -print0)
  if [[ "${#old_ipas[@]}" -gt 0 ]]; then
    preserved_directory=$(mktemp -d "$report_directory/preserved/attempt.XXXXXX")
    mv "${old_ipas[@]}" "$preserved_directory/"
  fi
fi

flutter build ipa \
  --release \
  --build-name "$VERSION_VALUE" \
  --build-number "$BUILD_VALUE" \
  --export-options-plist "$EXPORT_OPTIONS"

ipa_candidates=()
while IFS= read -r -d '' ipa_candidate; do
  ipa_candidates+=("$ipa_candidate")
done < <(find "$ipa_directory" -maxdepth 1 -type f -name '*.ipa' -print0)
if [[ "${#ipa_candidates[@]}" -ne 1 ]]; then
  echo "expected exactly one IPA in $ipa_directory, found ${#ipa_candidates[@]}" >&2
  exit 67
fi
candidate_ipa="$candidate_directory/$(basename "${ipa_candidates[0]}")"
mv "${ipa_candidates[0]}" "$candidate_ipa"
"$ROOT_DIR/scripts/release_contract_preflight.sh" ios "$VERSION_VALUE" "$BUILD_VALUE" build
ruby "$ROOT_DIR/scripts/verify_ios_ipa.rb" \
  "$candidate_ipa" \
  --bundle-id com.babycompany.yingjian \
  --version "$VERSION_VALUE" \
  --build "$BUILD_VALUE" \
  --team-id V86Q54AQQU \
  --firebase-config "$ROOT_DIR/ios/Runner/GoogleService-Info.plist" \
  --source-commit "$RELEASE_SOURCE_COMMIT" \
  --output "$report_path"

echo "LOCAL-ONLY complete: $candidate_ipa"
echo "Artifact report: $report_path"
