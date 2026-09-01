#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
TESTFLIGHT-UPLOAD BLOCKED: this legacy upload wrapper is disabled.
The former xcrun altool delivery path, including its processing wait, is forbidden.
Implement and verify the repository-owned Fastlane/Spaceship lane before enabling TestFlight upload.
Browser UI and manual upload are not fallback paths.
EOF

exit 78
