BIN       := macthermal
GUI_BIN   := macthermal-gui
APP       := MacThermal.app
TEST_BIN  := .macthermal-tests
PREFIX    ?= /usr/local

# Build for macOS 13+ regardless of the build SDK, so a newer-SDK release build
# (e.g. macos-26 → Tahoe SwiftUI styling) still launches on macOS 13. The
# explicit -target is required: swiftc ignores MACOSX_DEPLOYMENT_TARGET and
# otherwise defaults min-OS to the SDK version, silently raising the requirement.
ARCH   := $(shell uname -m)
DEPLOY := -target $(ARCH)-apple-macos13.0
# The actor / @MainActor / Sendable-value-model architecture is data-race clean,
# so the whole project builds under the Swift 6 language mode.
SWIFT6 := -swift-version 6

SHARED   := $(filter-out Sources/MacThermalCore/JSONReport.swift,$(wildcard Sources/MacThermalCore/*.swift))
REPORT   := Sources/MacThermalCore/JSONReport.swift
CLI_SRC  := $(SHARED) $(REPORT) Sources/macthermal/main.swift
GUI_SRC  := $(SHARED) $(wildcard Sources/macthermal-gui/*.swift)
TEST_SRC := $(SHARED) $(REPORT) Tests/Tests.swift

.PHONY: all build run watch test gui icon open clean install uninstall

all: build

# ---- CLI ----
build: $(BIN)

$(BIN): $(CLI_SRC)
	swiftc -O $(DEPLOY) $(SWIFT6) -framework IOKit -o $(BIN) $(CLI_SRC)

run: build
	./$(BIN)

watch: build
	./$(BIN) --watch 1

# ---- Tests (pure-logic, no SMC hardware required) ----
test: $(TEST_SRC)
	@swiftc $(SWIFT6) -parse-as-library -framework IOKit -o $(TEST_BIN) $(TEST_SRC)
	@./$(TEST_BIN)

# ---- Menu-bar GUI (.app bundle) ----
gui: $(APP)

$(APP): $(GUI_SRC) Resources/Info.plist Resources/AppIcon.icns
	swiftc -O $(DEPLOY) $(SWIFT6) -parse-as-library -framework IOKit -framework SwiftUI -framework AppKit \
		-framework ServiceManagement -framework Charts -framework UserNotifications \
		-o $(GUI_BIN) $(GUI_SRC)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	mv $(GUI_BIN) $(APP)/Contents/MacOS/$(GUI_BIN)
	codesign --force --sign - $(APP) >/dev/null 2>&1 || true
	@echo "built $(APP) — launch with: open $(APP)  (or: make open)"

# Regenerate the app icon from the SF Symbols thermometer (commits Resources/AppIcon.icns).
icon:
	./scripts/make-icon.sh

open: gui
	open $(APP)

# ---- housekeeping ----
clean:
	rm -rf $(BIN) $(GUI_BIN) $(APP) $(TEST_BIN)

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/$(BIN)
	@echo "installed to $(PREFIX)/bin/$(BIN)"

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)
