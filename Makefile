APP      := MouseFlow
APP_DIR  := build/$(APP).app
INSTALL  := $(HOME)/Applications/$(APP).app
# A stable identity keeps the Accessibility grant across rebuilds; "-" (ad-hoc) resets it every build.
SIGN_ID  ?= Apple Development
LOGO     := MouseFlow-Logo
VERSION  := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG      := build/$(APP)-$(VERSION).dmg
UNIVERSAL := build/universal/$(APP)

.PHONY: build app install run universal dist clean

build:
	swift build -c release

# $(1): the executable to package.
define package
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(1) $(APP_DIR)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(APP_DIR)/Contents/
	cp $(LOGO)/MouseFlow.icns $(APP_DIR)/Contents/Resources/AppIcon.icns
	cp $(LOGO)/MenuBarIcon.imageset/*.png $(APP_DIR)/Contents/Resources/
	codesign --force --sign "$(SIGN_ID)" $(APP_DIR)
endef

app: build
	$(call package,.build/release/$(APP))

install: app
	-pkill -x $(APP)
	mkdir -p $(HOME)/Applications
	rm -rf $(INSTALL)
	cp -R $(APP_DIR) $(INSTALL)

run: install
	open $(INSTALL)

# Command Line Tools can't build several architectures in one go, so build each slice and merge them.
universal:
	swift build -c release --triple arm64-apple-macosx14.0
	swift build -c release --triple x86_64-apple-macosx14.0
	mkdir -p $(dir $(UNIVERSAL))
	lipo -create -output $(UNIVERSAL) \
		.build/arm64-apple-macosx/release/$(APP) .build/x86_64-apple-macosx/release/$(APP)

# Drag-to-Applications disk image with a universal (Apple silicon + Intel) app.
dist: universal
	$(call package,$(UNIVERSAL))
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(APP_DIR) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname $(APP) -srcfolder build/dmg -ov -format UDZO $(DMG)
	rm -rf build/dmg

clean:
	rm -rf .build build
