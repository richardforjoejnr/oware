# __DISPLAY__ — per-app targets (also reachable from the repo root: make <target> APP=__SLUG__).
# The root Makefile forwards project, family, archive, test, open, clean and e2e* here, so every
# app answers all of them, even if only with a hint.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
SIM  = $$($(ROOT)/scripts/pick-simulator.sh)

.PHONY: project family archive test open clean e2e e2e-build e2e-studio e2e-ts

project:              ## Generate __NAME__.xcodeproj from project.yml
	xcodegen generate

test: project         ## Run unit + UI tests on a simulator
	set -o pipefail; xcodebuild test -project __NAME__.xcodeproj -scheme __NAME__ \
	  -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO | xcbeautify

open: project         ## Generate and open in Xcode
	open __NAME__.xcodeproj

# Upload from your Mac: a Release archive stamped with the same build-number scheme as CI (UTC date
# and time), opened in Xcode's Organizer. Then: Distribute App ▸ App Store Connect ▸ Upload.
# The marketing version stays whatever project.yml says (scripts/next_version.py reads this repo's
# single release line; give a second app its own tags before relying on it).
archive: project      ## Archive for TestFlight/App Store with a fresh build number, open in Organizer
	set -o pipefail; xcodebuild archive -project __NAME__.xcodeproj -scheme __NAME__ -configuration Release \
	  -destination 'generic/platform=iOS' -archivePath build/__NAME__.xcarchive -allowProvisioningUpdates \
	  CURRENT_PROJECT_VERSION=$$(date -u +%Y%m%d%H%M) | xcbeautify
	open build/__NAME__.xcarchive

# Free Apple IDs ("Personal Team") should not claim the real bundle id: this variant uses
# __BUNDLE__.family so the app installs on family iPhones from Xcode. If you add capabilities a
# Personal Team cannot sign (Game Center, iCloud, ...), strip their entitlements here as
# apps/lelu-oware/Makefile does.
family:               ## Xcode project for family iPhones with a free Apple ID
	xcodegen generate
	sed -i '' -e 's/PRODUCT_BUNDLE_IDENTIFIER = __BUNDLE__;/PRODUCT_BUNDLE_IDENTIFIER = __BUNDLE__.family;/' \
	  __NAME__.xcodeproj/project.pbxproj
	open __NAME__.xcodeproj

clean:
	rm -rf __NAME__.xcodeproj DerivedData build

e2e-build: project    ## Build a Debug simulator app into ./build (for Maestro / Appium suites)
	set -o pipefail; xcodebuild build -project __NAME__.xcodeproj -scheme __NAME__ -configuration Debug \
	  -destination "platform=iOS Simulator,name=$(SIM)" \
	  -derivedDataPath build CODE_SIGNING_ALLOWED=NO | xcbeautify

e2e e2e-studio e2e-ts: ## End-to-end suites: not set up for this app yet
	@echo "No end-to-end suite for __DISPLAY__ yet. Copy apps/lelu-oware/.maestro (for 'make e2e' / 'e2e-studio')"
	@echo "or apps/lelu-oware/e2e (for 'make e2e-ts') and the matching targets from apps/lelu-oware/Makefile."
	@exit 1
