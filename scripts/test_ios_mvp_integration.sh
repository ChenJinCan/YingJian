#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundle_id=com.babycompany.yingjian

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/test_ios_mvp_integration.sh IOS_SIMULATOR_ID" >&2
  exit 64
fi

simulator_id="$1"
if ! xcrun simctl list devices booted | grep -F "($simulator_id) (Booted)" >/dev/null; then
  echo "iOS Simulator $simulator_id must already be booted" >&2
  exit 65
fi

flutter_config_root=$(mktemp -d "${TMPDIR:-/tmp}/yingjian-ios-flutter-config.XXXXXX")
export XDG_CONFIG_HOME="$flutter_config_root"
flutter config --no-enable-android --enable-ios >/dev/null
flutter config --no-enable-swift-package-manager >/dev/null

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  flutter build ios --debug --simulator --config-only >/dev/null || status=$?
  if [ -d "$flutter_config_root" ]; then
    find "$flutter_config_root" -depth -delete
  fi
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

if ! xcrun simctl get_app_container "$simulator_id" "$bundle_id" app >/dev/null 2>&1; then
  (
    cd "$repo_root"
    flutter build ios --debug --simulator >/dev/null
  )
  xcrun simctl install "$simulator_id" "$repo_root/build/ios/iphonesimulator/Runner.app"
fi
xcrun simctl privacy "$simulator_id" grant photos-add "$bundle_id"

cd "$repo_root"
flutter test integration_test/ios_mvp_journey_test.dart -d "$simulator_id"
