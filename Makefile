APP_NAME = Audio Snitch
BUNDLE_NAME = AudioSnitch
CLI_BINARY = audiosnitch
APP_BUNDLE = $(BUNDLE_NAME).app
DMG_NAME = $(BUNDLE_NAME).dmg

CLI_SRC = audiosnitch.swift
APP_SRC = AudioSnitch/main.swift
APP_PLIST = AudioSnitch/Info.plist

.PHONY: all cli app dmg clean install uninstall

all: cli app

cli: $(CLI_BINARY)

$(CLI_BINARY): $(CLI_SRC)
	swiftc -O -o $@ $< -framework CoreAudio

app: $(APP_BUNDLE)

$(APP_BUNDLE): $(APP_SRC) $(APP_PLIST)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	swiftc -O -parse-as-library -o $(APP_BUNDLE)/Contents/MacOS/$(BUNDLE_NAME) $(APP_SRC) -framework CoreAudio
	@cp $(APP_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@cp AudioSnitch/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo

dmg: $(APP_BUNDLE)
	@rm -f $(DMG_NAME)
	@rm -rf dmg_temp
	@mkdir -p dmg_temp
	@cp -R $(APP_BUNDLE) dmg_temp/
	@ln -s /Applications dmg_temp/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder dmg_temp -ov -format UDZO $(DMG_NAME)
	@rm -rf dmg_temp
	@echo "Created $(DMG_NAME)"

clean:
	rm -f $(CLI_BINARY)
	rm -rf $(APP_BUNDLE)
	rm -f $(DMG_NAME)
	rm -rf dmg_temp

install: $(CLI_BINARY)
	cp $(CLI_BINARY) /usr/local/bin/

uninstall:
	rm -f /usr/local/bin/$(CLI_BINARY)
