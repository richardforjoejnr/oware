.PHONY: bootstrap project test engine-test open clean

bootstrap:            ## Install local tooling (Homebrew + Ruby gems)
	brew install xcodegen xcbeautify swiftlint
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
