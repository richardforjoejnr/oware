#!/usr/bin/env bash
# One-time local setup for contributors.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcode-select -p | grep -q "Xcode.app"; then
  echo "⚠️  Xcode is not the active developer directory. Install Xcode from the App Store, then run:"
  echo "    sudo xcode-select -s /Applications/Xcode.app"
fi
command -v brew >/dev/null || { echo "Homebrew required: https://brew.sh"; exit 1; }
brew install xcodegen xcbeautify swiftlint
command -v bundle >/dev/null && bundle install || echo "Install Ruby 3.x + bundler to use fastlane locally (optional)."
xcodegen generate
echo "✅ Done. Open Oware.xcodeproj or run: make open"
