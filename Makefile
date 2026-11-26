# Development commands. Run `make` or `make help` for the list.

SIMULATOR ?= iPad Pro 13-inch (M5)

# Several simulators can share a name, so the commands address one by identifier:
# a booted match if there is one, otherwise the first match.
SIMULATOR_ID = $(shell matches=$$(xcrun simctl list devices available | grep -F '$(SIMULATOR)'); \
	{ echo "$$matches" | grep Booted; echo "$$matches"; } \
	| grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1)

DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/Lined.app
XCODEBUILD = xcodebuild -project Lined.xcodeproj -scheme Lined \
	-destination 'platform=iOS Simulator,id=$(SIMULATOR_ID)' \
	-derivedDataPath $(DERIVED_DATA) -quiet

.DEFAULT_GOAL := help
.PHONY: help project simulator build test test-app run clean

help: ## List the commands
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "make %-9s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "SIMULATOR selects the simulator for build, test-app and run, by name or identifier."
	@echo "It defaults to \"$(SIMULATOR)\"."

project: ## Generate Lined.xcodeproj from project.yml
	xcodegen generate --quiet

simulator:
	@test -n "$(SIMULATOR_ID)" || { echo "No available simulator matches \"$(SIMULATOR)\"."; exit 1; }

build: project simulator ## Build the app for the simulator
	$(XCODEBUILD) build

test: ## Run the unit tests of LinedKit and the scripts on this Mac
	swift test --package-path Packages/LinedKit
	python3 -m unittest discover --start-directory scripts/tests --quiet

test-app: project simulator ## Run the app's tests in the simulator, with PencilKit and UIKit
	$(XCODEBUILD) test

run: build ## Build, install and launch the app in the simulator
	xcrun simctl boot $(SIMULATOR_ID) 2>/dev/null || true
	xcrun simctl install $(SIMULATOR_ID) '$(APP)'
	xcrun simctl launch $(SIMULATOR_ID) "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' '$(APP)/Info.plist')"

clean: project simulator ## Clean the build products
	$(XCODEBUILD) clean
	swift package --package-path Packages/LinedKit clean
