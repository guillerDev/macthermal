BIN      := macthermal
GUI_BIN  := macthermal-gui
APP      := macthermal.app
PREFIX   ?= /usr/local

SHARED   := Sources/SMC.swift Sources/Sensors.swift
CLI_SRC  := $(SHARED) Sources/main.swift
GUI_SRC  := $(SHARED) Sources/gui/MenuBarApp.swift

.PHONY: all build run watch gui open clean install uninstall

all: build

# ---- CLI ----
build: $(BIN)

$(BIN): $(CLI_SRC)
	swiftc -O -framework IOKit -o $(BIN) $(CLI_SRC)

run: build
	./$(BIN)

watch: build
	./$(BIN) --watch 1

# ---- Menu-bar GUI (.app bundle) ----
gui: $(APP)

$(APP): $(GUI_SRC) Resources/Info.plist
	swiftc -O -parse-as-library -framework IOKit -framework SwiftUI -framework AppKit \
		-o $(GUI_BIN) $(GUI_SRC)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	mv $(GUI_BIN) $(APP)/Contents/MacOS/$(GUI_BIN)
	codesign --force --sign - $(APP) >/dev/null 2>&1 || true
	@echo "built $(APP) — launch with: open $(APP)  (or: make open)"

open: gui
	open $(APP)

# ---- housekeeping ----
clean:
	rm -rf $(BIN) $(GUI_BIN) $(APP)

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/$(BIN)
	@echo "installed to $(PREFIX)/bin/$(BIN)"

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)
