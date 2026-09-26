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
for app in apps/*/; do (cd "$app" && xcodegen generate); done
echo "✅ Done. Open apps/<app>/*.xcodeproj or run: make open   (APP=lelu-oware by default)"
