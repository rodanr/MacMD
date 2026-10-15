# MacMD — common development tasks. Run `make help` for a list.

PROJECT   := MacMD.xcodeproj
SCHEME    := MacMD
DERIVED   := build/DerivedData
APP       := $(DERIVED)/Build/Products/Release/MacMD.app
DEBUG_APP := $(DERIVED)/Build/Products/Debug/MacMD.app
XCB       := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64'
SWIFT_SOURCES := App AppTests AppUITests Packages/MacMDKit/Sources Packages/MacMDKit/Tests Packages/MacMDKit/Package.swift

.PHONY: help setup build release run test test-kit test-app test-ui lint format dmg icon vendor prepare-release clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Generate the Xcode project (run after adding or removing files)
	@command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
	xcodegen generate --quiet

build: setup ## Debug build
	$(XCB) -configuration Debug build -quiet

release: setup ## Release build (arm64)
	$(XCB) -configuration Release build -quiet

run: build ## Build and launch the debug app
	open $(DEBUG_APP)

test: test-kit test-app test-ui ## Run all tests

test-kit: ## Run MacMDKit unit tests (fast, no Xcode project needed)
	cd Packages/MacMDKit && swift test

test-app: setup ## Run the app's unit tests (styling engine, inside the app)
	$(XCB) test -only-testing:MacMDTests -quiet

test-ui: setup ## Run the app's UI smoke tests
	$(XCB) test -only-testing:MacMDUITests -quiet

lint: ## Check formatting
	swift format lint --strict --recursive $(SWIFT_SOURCES)

format: ## Format all Swift sources in place
	swift format --in-place --recursive $(SWIFT_SOURCES)

dmg: release ## Build a distributable DMG in build/
	scripts/make-dmg.sh $(APP) build

icon: ## Render the app icon (App/Resources/AppIcon.icon, edit in Icon Composer) to docs/screenshots/icon.png
	rm -rf build/icon && mkdir -p build/icon
	xcrun actool $(CURDIR)/App/Resources/AppIcon.icon --compile $(CURDIR)/build/icon --platform macosx --minimum-deployment-target 26.0 \
		--app-icon AppIcon --output-partial-info-plist $(CURDIR)/build/icon/partial.plist >/dev/null
	swift scripts/render-icon-preview.swift build/icon docs/screenshots/icon.png

vendor: ## Re-download pinned reader libraries (highlight.js, KaTeX, Mermaid)
	scripts/vendor-web-assets.sh

prepare-release: ## Version, changelog, commit and tag for VERSION=X.Y.Z (never pushes)
	@test -n "$(VERSION)" || { echo "usage: make prepare-release VERSION=X.Y.Z"; exit 64; }
	scripts/prepare-release.sh $(VERSION)

clean: ## Remove build products
	rm -rf build $(PROJECT)
