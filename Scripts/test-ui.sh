#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project 'Music Analysis Studio.xcodeproj' -scheme 'Music Analysis Studio' -destination 'platform=macOS' \
  -parallel-testing-enabled NO -collect-test-diagnostics never -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 300 -derivedDataPath build -resultBundlePath build/Workflow-$(date +%s).xcresult test
