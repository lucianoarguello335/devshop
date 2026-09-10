CONFIG ?= release

.PHONY: build app universal dmg release run test icons catalog appicon install clean

build:
	swift build -c $(CONFIG)

app: build
	./Scripts/make-app.sh $(CONFIG)

# Both architectures in one bundle. Slower than `app`, so it is not part of the dev loop.
universal:
	DEVSHOP_UNIVERSAL=1 ./Scripts/make-app.sh release

dmg:
	./Scripts/make-dmg.sh

# Signed, notarized, stapled, ready to attach to a GitHub release.
# Add ARGS=--dry-run to rehearse the whole thing without a certificate.
release:
	./Scripts/release.sh $(ARGS)

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
	rm -rf .build DevShop.app dist
