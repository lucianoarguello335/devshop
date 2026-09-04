CONFIG ?= release

.PHONY: build app run test icons catalog appicon install clean

build:
	swift build -c $(CONFIG)

app: build
	./Scripts/make-app.sh $(CONFIG)

run: app
	open DevShop.app

# Replaces the copy the Dock points at. Run this after changing code, or the Dock icon
# keeps launching the previous build.
install: app
	pkill -x DevShop || true
	rm -rf /Applications/DevShop.app
	cp -R DevShop.app /Applications/DevShop.app
	codesign --force --sign - /Applications/DevShop.app
	@echo "installed /Applications/DevShop.app" 

test:
	swift test

icons:
	./Scripts/fetch-icons.sh

appicon:
	./Scripts/make-icon.sh

catalog:
	python3 Scripts/gen-catalog.py

clean:
	rm -rf .build DevShop.app
