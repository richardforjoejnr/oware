# __DISPLAY__ — per-app targets (also reachable from the repo root: make <target> APP=__SLUG__).
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
SIM  = $$($(ROOT)/scripts/pick-simulator.sh)

.PHONY: project test open clean

project:              ## Generate __NAME__.xcodeproj from project.yml
	xcodegen generate

test: project         ## Run unit + UI tests on a simulator
	set -o pipefail; xcodebuild test -project __NAME__.xcodeproj -scheme __NAME__ \
	  -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO | xcbeautify

open: project         ## Generate and open in Xcode
	open __NAME__.xcodeproj

clean:
	rm -rf __NAME__.xcodeproj DerivedData build
