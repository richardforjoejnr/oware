# Lelu Oware — per-app targets. Run from this directory, or from the repo root as `make <target>`
# (the root Makefile forwards to APP=lelu-oware by default).
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
SIM  = $$($(ROOT)/scripts/pick-simulator.sh)

.PHONY: project family archive test open clean e2e e2e-build e2e-studio e2e-ts

project:              ## Generate Oware.xcodeproj from project.yml
	xcodegen generate

test: project         ## Run app + engine tests on the simulator
	set -o pipefail; xcodebuild test -project Oware.xcodeproj -scheme Oware \
	  -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO | xcbeautify

open: project         ## Generate and open in Xcode
	open Oware.xcodeproj

# Upload from your Mac: a Release archive stamped with the same build-number scheme as CI (UTC date
# and time), opened in Xcode's Organizer. Then: Distribute App ▸ App Store Connect ▸ Upload.
archive: project      ## Archive for TestFlight/App Store with a fresh build number, open in Organizer
	set -o pipefail; xcodebuild archive -project Oware.xcodeproj -scheme Oware -configuration Release \
	  -destination 'generic/platform=iOS' -archivePath build/Oware.xcarchive -allowProvisioningUpdates \
	  CURRENT_PROJECT_VERSION=$$(date -u +%Y%m%d%H%M) MARKETING_VERSION=$$(python3 ../../scripts/next_version.py) | xcbeautify
	open build/Oware.xcarchive

# Free Apple IDs ("Personal Team") cannot sign Game Center, and should not claim the real bundle id.
# This project drops the Game Center entitlement and uses com.richardforjoe.oware.family, so the app
# installs on your own and family iPhones from Xcode before the paid membership exists.
family:               ## Xcode project for family iPhones with a free Apple ID (no Game Center)
	xcodegen generate
	sed -i '' -e '/CODE_SIGN_ENTITLEMENTS = /d' \
	  -e 's/PRODUCT_BUNDLE_IDENTIFIER = com.richardforjoe.oware;/PRODUCT_BUNDLE_IDENTIFIER = com.richardforjoe.oware.family;/' \
	  Oware.xcodeproj/project.pbxproj
	open Oware.xcodeproj

clean:
	rm -rf Oware.xcodeproj DerivedData build

e2e-build: project    ## Build a Debug simulator app into ./build (used by Maestro and the TS suite)
	set -o pipefail; xcodebuild build -project Oware.xcodeproj -scheme Oware -configuration Debug \
	  -destination "platform=iOS Simulator,name=$(SIM)" \
	  -derivedDataPath build CODE_SIGNING_ALLOWED=NO | xcbeautify

e2e: e2e-build        ## Install on a booted simulator and run Maestro flows
	xcrun simctl boot "$(SIM)" || true
	xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Oware.app
	maestro test .maestro

e2e-studio:           ## Open Maestro Studio to author flows interactively against the booted simulator
	maestro studio

e2e-ts: e2e-build     ## Run the TypeScript Appium + WebdriverIO suite (cd e2e && npm install first)
	cd e2e && npm test
