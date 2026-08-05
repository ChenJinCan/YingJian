#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/load_testflight_environment.sh"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

IPA_PATH="${1:-}"
REPORT_PATH="${2:-}"
VERSION_VALUE="${3:-}"
BUILD_VALUE="${4:-}"
if ! [[ "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must use x.y.z format" >&2
  exit 64
fi
if ! [[ "$BUILD_VALUE" =~ ^[1-9][0-9]*$ ]]; then
  echo "build must be a positive integer" >&2
  exit 64
fi

print_plan() {
  cat <<EOF
TESTFLIGHT-UPLOAD: validate and upload exactly one previously verified IPA, then wait on that delivery.
release_contract_preflight.sh ios $VERSION_VALUE $BUILD_VALUE upload
verify_ios_ipa.rb $IPA_PATH --bundle-id com.babycompany.yingjian --version $VERSION_VALUE --build $BUILD_VALUE --source-commit <RELEASE_SOURCE_COMMIT> --firebase-config ios/Runner/GoogleService-Info.plist --expected-sha256 <REPORT_SHA256>
altool --validate-app $IPA_PATH --output-format json
altool --upload-package $IPA_PATH --wait --output-format json
check_altool_delivery.rb <delivery.json> --output <normalized-status.json>
Terminal boundary: provider valid only; no test-group distribution, metadata, App Review, or public release.
EOF
}

if [[ "$DRY_RUN" == true ]]; then
  print_plan
  exit 0
fi

cd "$ROOT_DIR"
load_testflight_environment "$ROOT_DIR"
: "${RELEASE_SOURCE_COMMIT:?freeze the exact pushed source commit before upload}"
: "${ASC_KEY_ID:?configure ASC_KEY_ID in the ignored .env.testflight}"
: "${ASC_ISSUER_ID:?configure ASC_ISSUER_ID in the ignored .env.testflight}"
: "${ASC_KEY_PATH:?configure ASC_KEY_PATH in the ignored .env.testflight}"
[[ -f "$IPA_PATH" ]] || { echo "IPA does not exist: $IPA_PATH" >&2; exit 66; }
[[ -f "$REPORT_PATH" ]] || { echo "artifact report does not exist: $REPORT_PATH" >&2; exit 66; }
[[ -f "$ASC_KEY_PATH" ]] || { echo "App Store Connect key file is missing" >&2; exit 66; }

echo "APPLE READ-ONLY: revalidating iOS candidate $VERSION_VALUE ($BUILD_VALUE) before upload."
"$ROOT_DIR/scripts/release_contract_preflight.sh" ios "$VERSION_VALUE" "$BUILD_VALUE" upload

report_values=$(ruby -rjson -e '
  report = JSON.parse(File.read(ARGV.fetch(0)))
  expected = [ARGV.fetch(1), ARGV.fetch(2), ARGV.fetch(3)]
  actual = [report.fetch("version"), report.fetch("build"), report.fetch("source_commit")]
  abort "artifact report identity does not match the requested candidate" unless actual == expected
  sha = report.fetch("sha256")
  abort "artifact report SHA-256 is invalid" unless sha.match?(/\A[0-9a-f]{64}\z/)
  puts sha
' "$REPORT_PATH" "$VERSION_VALUE" "$BUILD_VALUE" "$RELEASE_SOURCE_COMMIT")

ruby "$ROOT_DIR/scripts/verify_ios_ipa.rb" \
  "$IPA_PATH" \
  --bundle-id com.babycompany.yingjian \
  --version "$VERSION_VALUE" \
  --build "$BUILD_VALUE" \
  --team-id V86Q54AQQU \
  --firebase-config "$ROOT_DIR/ios/Runner/GoogleService-Info.plist" \
  --source-commit "$RELEASE_SOURCE_COMMIT" \
  --expected-sha256 "$report_values"

candidate_upload_directory="$ROOT_DIR/.release-state/ios/uploads/$VERSION_VALUE-$BUILD_VALUE"
mkdir -p "$candidate_upload_directory"
upload_directory=$(mktemp -d "$candidate_upload_directory/attempt.XXXXXX")

echo "APPLE READ-ONLY: asking Apple to validate the exact IPA."
xcrun altool \
  --validate-app "$IPA_PATH" \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" \
  --p8-file-path "$ASC_KEY_PATH" \
  --output-format json 2>&1 | tee "$upload_directory/validation.json"

echo "TESTFLIGHT-UPLOAD: uploading the verified IPA and waiting for the same delivery to finish processing."
xcrun altool \
  --upload-package "$IPA_PATH" \
  --wait \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" \
  --p8-file-path "$ASC_KEY_PATH" \
  --output-format json 2>&1 | tee "$upload_directory/delivery.json"

ruby "$ROOT_DIR/scripts/check_altool_delivery.rb" \
  "$upload_directory/delivery.json" \
  --version "$VERSION_VALUE" \
  --build "$BUILD_VALUE" \
  --source-commit "$RELEASE_SOURCE_COMMIT" \
  --sha256 "$report_values" \
  --output "$upload_directory/status.json"

echo "TESTFLIGHT-UPLOAD provider-valid result recorded at $upload_directory/status.json"
echo "Test-group distribution and real tester reachability remain unverified. No metadata was uploaded and App Review was not submitted."
