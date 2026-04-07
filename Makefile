APP_NAME = PillFloat
APP_BUNDLE = build/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)
INSTALL_DIR = /Applications

.PHONY: build app install uninstall clean

build:
	swift build -c release

app: build
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	@cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/"
	@echo "Built $(APP_BUNDLE)"

install: app
	@if command -v brew >/dev/null 2>&1 && brew list --cask pillfloat >/dev/null 2>&1; then \
		echo "Error: PillFloat is already installed via Homebrew."; \
		echo "Run 'brew uninstall --cask pillfloat' first, or use 'brew upgrade --cask pillfloat' to update."; \
		exit 1; \
	fi
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "You can now find 'PillFloat' in Spotlight."

uninstall:
	@if command -v brew >/dev/null 2>&1 && brew list --cask pillfloat >/dev/null 2>&1; then \
		echo "PillFloat is managed by Homebrew. Run 'brew uninstall --cask pillfloat' instead."; \
		exit 1; \
	fi
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Uninstalled $(APP_NAME).app from $(INSTALL_DIR)"

clean:
	swift package clean
	@rm -rf build/
