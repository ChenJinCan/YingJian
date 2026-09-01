#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
TESTFLIGHT-UPLOAD BLOCKED: this legacy upload wrapper is disabled.
The former xcrun altool delivery path, including its processing wait, is forbidden.
The repository-owned Fastlane/Spaceship lane is the only permitted upload path and remains subject to every release gate.
Browser UI and manual upload are not fallback paths.
EOF

exit 78
