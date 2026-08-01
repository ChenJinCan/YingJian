#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRE_CONFIGURED=false
if [[ "${1:-}" == "--require-configured" ]]; then
  REQUIRE_CONFIGURED=true
fi

missing=()
for path in \
  android/app/google-services.json \
  ios/Runner/GoogleService-Info.plist \
  lib/firebase_options.dart; do
  [[ -f "$ROOT_DIR/$path" ]] || missing+=("$path")
done

required_patterns=(
  "android/app/src/main/AndroidManifest.xml|firebase_analytics_collection_enabled"
  "android/app/src/main/AndroidManifest.xml|firebase_crashlytics_collection_enabled"
  "android/app/src/main/AndroidManifest.xml|firebase_performance_collection_enabled"
  "ios/Runner/Info.plist|FIREBASE_ANALYTICS_COLLECTION_ENABLED"
  "ios/Runner/Info.plist|FirebaseCrashlyticsCollectionEnabled"
  "ios/Runner/Info.plist|firebase_performance_collection_enabled"
)
for requirement in "${required_patterns[@]}"; do
  file="${requirement%%|*}"
  pattern="${requirement#*|}"
  if ! rg -Fq "$pattern" "$ROOT_DIR/$file"; then
    echo "BLOCKED: missing privacy-first Firebase setting $pattern in $file" >&2
    exit 1
  fi
done

if ((${#missing[@]} > 0)); then
  echo "Firebase remote configuration is not installed: ${missing[*]}"
  if [[ "$REQUIRE_CONFIGURED" == true ]]; then
    echo "BLOCKED: run flutterfire configure for the approved Yingjian Firebase project." >&2
    exit 1
  fi
  exit 0
fi

if ! rg -Fq "com.babycompany.yingjian" "$ROOT_DIR/android/app/google-services.json"; then
  echo "BLOCKED: Android Firebase configuration does not match Yingjian." >&2
  exit 1
fi
if ! rg -Fq "com.babycompany.yingjian" "$ROOT_DIR/ios/Runner/GoogleService-Info.plist"; then
  echo "BLOCKED: iOS Firebase configuration does not match Yingjian." >&2
  exit 1
fi

build_integrations=(
  "android/settings.gradle.kts|com.google.gms.google-services"
  "android/settings.gradle.kts|com.google.firebase.crashlytics"
  "android/settings.gradle.kts|com.google.firebase.firebase-perf"
  "android/app/build.gradle.kts|com.google.gms.google-services"
  "android/app/build.gradle.kts|com.google.firebase.crashlytics"
  "android/app/build.gradle.kts|com.google.firebase.firebase-perf"
  "ios/Runner.xcodeproj/project.pbxproj|FirebaseCrashlytics/run"
)
for integration in "${build_integrations[@]}"; do
  file="${integration%%|*}"
  pattern="${integration#*|}"
  if ! rg -Fq "$pattern" "$ROOT_DIR/$file"; then
    echo "BLOCKED: Firebase build integration $pattern is missing from $file" >&2
    exit 1
  fi
done

echo "Firebase configuration files and privacy-first defaults are present."
