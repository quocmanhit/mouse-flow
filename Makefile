APP      := MouseFlow
APP_DIR  := build/$(APP).app
INSTALL  := $(HOME)/Applications/$(APP).app
# A stable identity keeps the Accessibility grant across rebuilds; "-" (ad-hoc) resets it every build.
SIGN_ID  ?= Apple Development
LOGO     := MouseFlow-Logo

.PHONY: build app install run clean

build:
	swift build -c release

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS
	cp .build/release/$(APP) $(APP_DIR)/Contents/MacOS/
	cp Resources/Info.plist $(APP_DIR)/Contents/
	mkdir -p $(APP_DIR)/Contents/Resources
	cp $(LOGO)/MouseFlow.icns $(APP_DIR)/Contents/Resources/AppIcon.icns
	cp $(LOGO)/MenuBarIcon.imageset/*.png $(APP_DIR)/Contents/Resources/
	codesign --force --sign "$(SIGN_ID)" $(APP_DIR)

install: app
	-pkill -x $(APP)
	mkdir -p $(HOME)/Applications
	rm -rf $(INSTALL)
	cp -R $(APP_DIR) $(INSTALL)

run: install
	open $(INSTALL)

clean:
	rm -rf .build build
