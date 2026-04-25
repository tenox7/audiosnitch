-include .env

APP_NAME = Audio Snitch
BUNDLE_NAME = AudioSnitch
APP_BUNDLE = $(BUNDLE_NAME).app
DMG_NAME = $(BUNDLE_NAME).dmg
STAGING = dmg_staging

APP_SRC = AudioSnitch/main.swift
APP_PLIST = AudioSnitch/Info.plist
APP_ICON = AudioSnitch/AppIcon.icns

.PHONY: all app dmg release clean

all: app

app: $(APP_BUNDLE)

$(APP_BUNDLE): $(APP_SRC) $(APP_PLIST) $(APP_ICON)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	swiftc -O -parse-as-library -o $(APP_BUNDLE)/Contents/MacOS/$(BUNDLE_NAME) $(APP_SRC) -framework CoreAudio
	@cp $(APP_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@cp $(APP_ICON) $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	codesign --force --sign - $(APP_BUNDLE)

define build_dmg
	@rm -rf $(STAGING) $(1)
	@mkdir -p $(STAGING)
	cp -R $(APP_BUNDLE) $(STAGING)/
	ln -s /Applications $(STAGING)/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(STAGING) -ov -format UDZO $(1)
	@rm -rf $(STAGING)
endef

dmg: $(APP_BUNDLE)
	$(call build_dmg,$(DMG_NAME))
	@echo "Created $(DMG_NAME)"

release: $(APP_SRC) $(APP_PLIST) $(APP_ICON)
	@test -n "$(DEV_ID)" || { echo "DEV_ID not set — copy .env.example to .env and fill in"; exit 1; }
	@test -n "$(NOTARY_PROFILE)" || { echo "NOTARY_PROFILE not set — copy .env.example to .env and fill in"; exit 1; }
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	swiftc -O -parse-as-library -o $(APP_BUNDLE)/Contents/MacOS/$(BUNDLE_NAME) $(APP_SRC) -framework CoreAudio
	@cp $(APP_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@cp $(APP_ICON) $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	codesign --force --options runtime --timestamp --sign "$(DEV_ID)" $(APP_BUNDLE)
	$(call build_dmg,$(DMG_NAME))
	codesign --force --timestamp --sign "$(DEV_ID)" $(DMG_NAME)
	xcrun notarytool submit $(DMG_NAME) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(DMG_NAME)
	@echo "Signed + notarized: $(DMG_NAME)"

clean:
	rm -rf $(APP_BUNDLE)
	rm -f $(DMG_NAME)
	rm -rf $(STAGING)
