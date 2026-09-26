# Monorepo root. `make <target>` forwards to apps/$(APP) (default lelu-oware).
#   make test APP=lelu-oware      make open      make engine-test      make new-app NAME=my-app
APP ?= lelu-oware
APP_DIR := apps/$(APP)

.PHONY: help bootstrap apps project test open clean e2e e2e-build e2e-studio e2e-ts engine-test new-app

help:                 ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

bootstrap:            ## Install local tooling and generate every app's Xcode project
	scripts/bootstrap.sh

apps:                 ## List the apps in this repo
	@ls -1 apps

engine-test:          ## Shared package tests (Command Line Tools are enough)
	cd packages/OwareEngine && swift test --parallel
	cd packages/SupportKit && swift test

project test open clean e2e e2e-build e2e-studio e2e-ts:   ## Forwarded to apps/$(APP)
	$(MAKE) -C $(APP_DIR) $@

new-app:              ## Scaffold apps/$(NAME) from templates/ios-app (NAME=my-app DISPLAY="My App")
	scripts/new-app.sh "$(NAME)" "$(DISPLAY)"
