#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundle_id=com.babycompany.yingjian

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/test_ios_normal_startup.sh IOS_SIMULATOR_ID" >&2
  exit 64
fi

simulator_id=$1
if ! xcrun simctl list devices booted | grep -F "($simulator_id) (Booted)" >/dev/null; then
  echo "iOS Simulator $simulator_id must already be booted" >&2
  exit 65
fi

evidence_dir=$(mktemp -d "${TMPDIR:-/tmp}/yingjian-ios-startup.XXXXXX")
cleanup() {
  if [ -d "$evidence_dir" ]; then
    find "$evidence_dir" -depth -delete
  fi
}
trap cleanup EXIT HUP INT TERM

cd "$repo_root"
flutter build ios --debug --simulator
app_path="$repo_root/build/ios/iphonesimulator/Runner.app"
if [ ! -d "$app_path" ]; then
  echo "Normal iOS Simulator app was not built" >&2
  exit 66
fi

xcrun simctl terminate "$simulator_id" "$bundle_id" >/dev/null 2>&1 || true
xcrun simctl install "$simulator_id" "$app_path"
xcrun simctl launch "$simulator_id" "$bundle_id" >/dev/null

attempt=1
while [ "$attempt" -le 5 ]; do
  sleep 1
  screenshot="$evidence_dir/startup-$attempt.png"
  xcrun simctl io "$simulator_id" screenshot "$screenshot" >/dev/null
  if xcrun swift scripts/check_ios_startup_screenshot.swift "$screenshot"; then
    echo "Normal iOS Simulator app startup passed."
    exit 0
  fi
  attempt=$((attempt + 1))
done

echo "Normal iOS Simulator app remained blank after five checks" >&2
exit 1
