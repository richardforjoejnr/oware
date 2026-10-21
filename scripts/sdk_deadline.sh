#!/usr/bin/env bash
# Apple's minimum SDK for App Store uploads (developer.apple.com/news, 2026-09-09): from April 2027,
# apps must be built with the iOS 27 SDK or later. Warns on every upload before then; fails after.
# Moving on means a runner with Xcode 27 (runs-on: macos-26) in the TestFlight workflows.
set -euo pipefail
REQUIRED_MAJOR=27
DEADLINE=2027-04-01

sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
major="${sdk%%.*}"
echo "Building with the iOS $sdk SDK ($(xcodebuild -version | head -1))"
if (( major >= REQUIRED_MAJOR )); then
  exit 0
fi
if [[ "$(date -u +%F)" < "$DEADLINE" ]]; then
  echo "::warning::iOS $sdk SDK: from April 2027 the App Store takes only builds made with the iOS $REQUIRED_MAJOR SDK or later. Move the TestFlight workflows to a runner with Xcode $REQUIRED_MAJOR before then."
else
  echo "::error::iOS $sdk SDK: the App Store now requires the iOS $REQUIRED_MAJOR SDK or later. Move the TestFlight workflows to a runner with Xcode $REQUIRED_MAJOR."
  exit 1
fi
