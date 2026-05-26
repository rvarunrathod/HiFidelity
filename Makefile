# HiFidelity — local install helpers.
# `make install` builds the Release .app and copies it to /Applications.
# Signing: ad-hoc by default (matches project default). Override by exporting
# HiFidelity_TEAM_ID and HiFidelity_DEVELOPER_ID before invoking.

APP_NAME    := HiFidelity
PROJECT     := $(APP_NAME).xcodeproj
SCHEME      := $(APP_NAME)
CONFIG      := Release
BUILD_DIR   := build/make
DERIVED     := $(BUILD_DIR)/DerivedData
APP_PATH    := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
INSTALL_DIR := /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app

TEAM_ID     ?= $(HiFidelity_TEAM_ID)
DEVELOPER_ID?= $(HiFidelity_DEVELOPER_ID)

ifneq ($(strip $(DEVELOPER_ID)),)
ifneq ($(DEVELOPER_ID),-)
SIGN_FLAGS := DEVELOPMENT_TEAM='$(TEAM_ID)' \
              CODE_SIGN_IDENTITY='$(DEVELOPER_ID)' \
              CODE_SIGN_STYLE=Manual \
              ENABLE_HARDENED_RUNTIME=YES \
              OTHER_CODE_SIGN_FLAGS='--timestamp --options=runtime'
endif
endif
SIGN_FLAGS ?= CODE_SIGN_IDENTITY='-' CODE_SIGN_STYLE=Automatic ENABLE_HARDENED_RUNTIME=YES

.PHONY: install build clean uninstall print-app

install: build
	@echo "→ Quitting running $(APP_NAME) (if any)…"
	@osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || true
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@if [ -d "$(INSTALLED)" ]; then \
	  echo "→ Removing existing $(INSTALLED)"; \
	  rm -rf "$(INSTALLED)"; \
	fi
	@echo "→ Installing to $(INSTALLED)"
	@cp -R "$(APP_PATH)" "$(INSTALLED)"
	@echo "✅ Installed $(APP_NAME) → $(INSTALLED)"

build:
	@mkdir -p "$(BUILD_DIR)"
	xcodebuild build \
	  -project "$(PROJECT)" \
	  -scheme "$(SCHEME)" \
	  -configuration "$(CONFIG)" \
	  -derivedDataPath "$(DERIVED)" \
	  -destination 'platform=macOS' \
	  ARCHS='x86_64 arm64' \
	  ONLY_ACTIVE_ARCH=NO \
	  $(SIGN_FLAGS)
	@test -d "$(APP_PATH)" || { echo "❌ Build did not produce $(APP_PATH)"; exit 1; }

clean:
	rm -rf "$(BUILD_DIR)"

uninstall:
	@osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || true
	@pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf "$(INSTALLED)"
	@echo "✅ Removed $(INSTALLED)"

print-app:
	@echo "$(APP_PATH)"
