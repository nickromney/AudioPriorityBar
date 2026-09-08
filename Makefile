SHELL := /bin/bash

MAKE_KNOWN_GOALS := help build dist install dev run test clean

APP_NAME := AudioPriorityBar
PROJECT := AudioPriorityBar.xcodeproj
SCHEME := AudioPriorityBar
BUILD_DIR := .build
DIST_DIR := dist
DEV_APP := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app
DIST_APP := $(DIST_DIR)/$(APP_NAME).app
INSTALLED_APP := $(HOME)/Applications/$(APP_NAME).app
MACOS_DESTINATION := platform=macOS,arch=arm64

.DEFAULT_GOAL := default

.PHONY: default help build dist install dev run test clean

default:
	@$(MAKE) --no-print-directory help

help:
	@echo "Audio Priority Bar Makefile guide"
	@echo ""
	@printf '%b\n' \
		'make dev\tBuild, install, and launch the current Debug app' \
		'make run\tAlias for make dev' \
		'make build\tBuild the Debug app without installing it' \
		'make dist\tBuild the Release app into dist/ for GitHub artifacts' \
		'make install\tInstall the current dist/ app into ~/Applications' \
		'make test\tRun the Xcode test target' \
		'make clean\tRemove local build and distribution artifacts' \
	| while IFS=$$'\t' read -r command description; do \
		printf '  %-16s %s\n' "$$command" "$$description"; \
	done

build:
	@xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(MACOS_DESTINATION)" \
		-configuration Debug \
		-derivedDataPath "$(BUILD_DIR)" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		build

dist:
	@xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-derivedDataPath "$(BUILD_DIR)" \
		-arch arm64 -arch x86_64 \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		build
	@mkdir -p "$(DIST_DIR)"
	@rm -rf "$(DIST_APP)"
	@ditto "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app" "$(DIST_APP)"
	@echo "Built $(DIST_APP)"

install: dist
	@mkdir -p "$(HOME)/Applications"
	@rm -rf "$(INSTALLED_APP)"
	@ditto "$(DIST_APP)" "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"

dev: build
	@mkdir -p "$(HOME)/Applications"
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	@for attempt in {1..100}; do \
		if ! pgrep -x "$(APP_NAME)" >/dev/null; then break; fi; \
		sleep 0.1; \
	done; \
	if pgrep -x "$(APP_NAME)" >/dev/null; then \
		echo "Audio Priority Bar did not quit. Quit it and run make dev again." >&2; \
		exit 1; \
	fi
	@rm -rf "$(INSTALLED_APP)"
	@ditto "$(DEV_APP)" "$(INSTALLED_APP)"
	@open -n "$(INSTALLED_APP)"
	@echo "Running $(INSTALLED_APP)"

run: dev

test:
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	@xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(MACOS_DESTINATION)" \
		-derivedDataPath "$(BUILD_DIR)" \
		CODE_SIGNING_ALLOWED=NO \
		test

clean:
	@rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"
