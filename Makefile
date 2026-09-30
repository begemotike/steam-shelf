PROJECT  := SteamShelf.xcodeproj
SCHEME   := SteamShelf
DERIVED  := build
APP      := $(DERIVED)/Build/Products/Debug/SteamShelf.app
XCB      := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
			-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64'

.PHONY: all gen build test run demo path clean

all: test build path

gen:
	xcodegen generate --quiet

build: gen
	$(XCB) build -quiet

test: gen
	$(XCB) test -quiet

path:
	@echo "Built app: $(abspath $(APP))"

run: build
	open "$(APP)"

demo: build
	open "$(APP)" --args --demo

clean:
	rm -rf $(DERIVED) $(PROJECT)
