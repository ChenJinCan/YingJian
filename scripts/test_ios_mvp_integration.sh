#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/test_ios_mvp_integration.sh IOS_SIMULATOR_ID" >&2
  exit 64
fi

simulator_id="$1"
if ! xcrun simctl list devices booted | grep -F "($simulator_id) (Booted)" >/dev/null; then
  echo "iOS Simulator $simulator_id must already be booted" >&2
  exit 65
fi

restore_normal_flutter_target() {
  flutter build ios --debug --simulator --config-only >/dev/null
}
trap restore_normal_flutter_target EXIT HUP INT TERM

flutter test integration_test/ios_mvp_journey_test.dart -d "$simulator_id"
