.PHONY: bootstrap project test engine-test open clean e2e e2e-build e2e-studio e2e-ts

bootstrap:            ## Install local tooling (Homebrew + Ruby gems)
	brew install xcodegen xcbeautify swiftlint mobile-dev-inc/tap/maestro
	bundle install

project:              ## Generate Oware.xcodeproj from project.yml
	xcodegen generate

engine-test:          ## Run the rules-engine tests (works without Xcode, only Command Line Tools)
	cd Packages/OwareEngine && swift test --parallel

test: project         ## Run app + engine tests on the simulator
	set -o pipefail; xcodebuild test -project Oware.xcodeproj -scheme Oware \
	  -destination "platform=iOS Simulator,name=$$(scripts/pick-simulator.sh)" CODE_SIGNING_ALLOWED=NO | xcbeautify

open: project         ## Generate and open in Xcode
	open Oware.xcodeproj

clean:
	rm -rf Oware.xcodeproj DerivedData Packages/OwareEngine/.build

e2e-build: project    ## Build a Debug simulator app into ./build (used by Maestro and the TS suite)
	set -o pipefail; xcodebuild build -project Oware.xcodeproj -scheme Oware -configuration Debug \
	  -destination "platform=iOS Simulator,name=$$(scripts/pick-simulator.sh)" \
	  -derivedDataPath build CODE_SIGNING_ALLOWED=NO | xcbeautify

e2e: e2e-build        ## Install on a booted simulator and run Maestro flows
	xcrun simctl boot "$$(scripts/pick-simulator.sh)" || true
	xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Oware.app
	maestro test .maestro

e2e-studio:           ## Open Maestro Studio to author flows interactively against the booted simulator
	maestro studio

e2e-ts: e2e-build     ## Run the TypeScript Appium + WebdriverIO suite (cd e2e && npm install first)
	cd e2e && npm test
