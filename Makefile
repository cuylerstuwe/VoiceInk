# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_APP ?= /Applications/VoiceInk.app
LOCAL_CODESIGN_IDENTITY ?=
RUN_APP_NAME ?= VoiceInk

.PHONY: all clean whisper setup build local check healthcheck help dev run release release-setup

# Default target
all: check build

# Development workflow
dev: RUN_APP_NAME = VoiceInk Dev
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build

# Build locally with stable Apple Development signing when available.
local: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	@SIGNING_IDENTITY="$(LOCAL_CODESIGN_IDENTITY)"; \
	if [ -z "$$SIGNING_IDENTITY" ]; then \
		SIGNING_IDENTITIES=$$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: / { print $$2 }'); \
		SIGNING_IDENTITY_COUNT=$$(printf '%s\n' "$$SIGNING_IDENTITIES" | awk 'NF { count++ } END { print count + 0 }'); \
		if [ "$$SIGNING_IDENTITY_COUNT" -eq 1 ]; then \
			SIGNING_IDENTITY=$$(printf '%s\n' "$$SIGNING_IDENTITIES" | awk 'NF { print; exit }'); \
		elif [ "$$SIGNING_IDENTITY_COUNT" -gt 1 ]; then \
			echo "Multiple Apple Development identities found; set LOCAL_CODESIGN_IDENTITY to choose one; using ad-hoc signing"; \
		fi; \
	fi; \
	if [ -n "$$SIGNING_IDENTITY" ] && [ "$$SIGNING_IDENTITY" != "-" ]; then \
		SIGNING_REQUIRED=YES; \
		echo "Using stable local signing identity: $$SIGNING_IDENTITY"; \
	else \
		SIGNING_IDENTITY="-"; \
		SIGNING_REQUIRED=NO; \
		echo "Using ad-hoc signing (permissions may need approval after rebuilds)"; \
	fi; \
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="$$SIGNING_IDENTITY" \
		CODE_SIGNING_REQUIRED="$$SIGNING_REQUIRED" \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		ONLY_ACTIVE_ARCH=YES \
		ARCHS=arm64 \
		ENABLE_HARDENED_RUNTIME=NO \
		ENABLE_TESTABILITY=NO \
		ENABLE_CODE_COVERAGE=NO \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Release/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		if pgrep -x VoiceInk >/dev/null 2>&1; then \
			echo "VoiceInk is running. Quit it before replacing $(LOCAL_APP)."; \
			exit 1; \
		fi; \
		echo "Installing the canonical local build at $(LOCAL_APP)..."; \
		rm -rf "$(LOCAL_APP)"; \
		ditto "$$APP_PATH" "$(LOCAL_APP)"; \
		xattr -cr "$(LOCAL_APP)"; \
		LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"; \
		"$$LSREGISTER" -u "$$APP_PATH" >/dev/null 2>&1 || true; \
		"$$LSREGISTER" -f -R -trusted "$(LOCAL_APP)"; \
		echo ""; \
		echo "Build complete! App installed at: $(LOCAL_APP)"; \
		echo "Run with: open $(LOCAL_APP)"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ "$(RUN_APP_NAME)" != "VoiceInk" ]; then \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "$(RUN_APP_NAME).app" -type d -print -quit); \
		if [ -z "$$APP_PATH" ]; then echo "$(RUN_APP_NAME).app not found. Run make dev first."; exit 1; fi; \
		open "$$APP_PATH"; \
	elif [ -d "$(LOCAL_APP)" ]; then \
		echo "Opening $(LOCAL_APP)..."; \
		open "$(LOCAL_APP)"; \
	else \
		echo "VoiceInk.app not found at $(LOCAL_APP). Please run 'make local' first."; \
		exit 1; \
	fi

# Build a signed, notarized DMG and matching local Sparkle Appcast.
release: whisper
	@if [ -n "$(NOTES)" ]; then \
		./scripts/release.sh --notes "$(NOTES)" $(RELEASE_ARGS); \
	else \
		./scripts/release.sh $(RELEASE_ARGS); \
	fi

# Store Apple's notarization credentials securely in Keychain.
release-setup:
	@./scripts/setup-release-notarization.sh

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build and install the one local app at $(LOCAL_APP)"
	@echo "  run                Launch $(LOCAL_APP)"
	@echo "    LOCAL_CODESIGN_IDENTITY=<SHA or name> overrides automatic Apple Development detection"
	@echo "  dev                Build and run the app (for development)"
	@echo "  release            Build DMG and Appcast using release-notes/<version>.html"
	@echo "  release-setup      Store notarization credentials in Keychain"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
