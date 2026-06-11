.PHONY: help build run stop restart smoke test-window test-window-ui test-window-focus test-flux release release-dry clean

PROJECT := Gojo.xcodeproj
SCHEME := Gojo
CONFIGURATION := Debug
DERIVED_DATA_PATH := .build/DerivedData
APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)/Gojo.app

help:
	@echo "Gojo local commands:"
	@echo "  make build       Build the Debug macOS app"
	@echo "  make run         Build, replace any running Gojo, then launch"
	@echo "  make stop        Stop running Gojo dev app processes"
	@echo "  make restart     Stop, build, and launch the app"
	@echo "  make smoke       Build, launch, verify process, then stop"
	@echo "  make test-window Run window management regression checks"
	@echo "  make test-window-ui Run Windows tab UI regression checks"
	@echo "  make test-window-focus Run focused-window provider regression checks"
	@echo "  make test-flux   Run flux night shift regression checks"
	@echo ""
	@echo "Release:"
	@echo "  make release VERSION=x.y.z      Cut a signed/notarized release (see RELEASING.md)"
	@echo "  make release-dry VERSION=x.y.z  Build + sign + notarize without publishing"
	@echo ""
	@echo "  make clean       Remove local build artifacts"

release:
	@test -n "$(VERSION)" || (echo "Usage: make release VERSION=x.y.z"; exit 2)
	@./scripts/release.sh $(VERSION)

release-dry:
	@test -n "$(VERSION)" || (echo "Usage: make release-dry VERSION=x.y.z"; exit 2)
	@DRY_RUN=1 ./scripts/release.sh $(VERSION)

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination 'platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		build

run: build
	$(MAKE) stop
	open "$(APP_PATH)"

stop:
	@for pattern in \
		'/Gojo\.app/Contents/MacOS/Gojo' \
		'/Gojo\.app/Contents/XPCServices/GojoXPCHelper\.xpc/Contents/MacOS/GojoXPCHelper' \
		'/Gojo\.app/Contents/Resources/mediaremote-adapter\.pl' \
		'/Gojo\.app/Contents/Frameworks/Sparkle\.framework/.*/Downloader'; do \
		pids=$$(pgrep -f "$$pattern" || true); \
		if [ -n "$$pids" ]; then kill $$pids 2>/dev/null || true; fi; \
	done
	@sleep 0.5
	@for pattern in \
		'/Gojo\.app/Contents/MacOS/Gojo' \
		'/Gojo\.app/Contents/XPCServices/GojoXPCHelper\.xpc/Contents/MacOS/GojoXPCHelper' \
		'/Gojo\.app/Contents/Resources/mediaremote-adapter\.pl' \
		'/Gojo\.app/Contents/Frameworks/Sparkle\.framework/.*/Downloader'; do \
		pids=$$(pgrep -f "$$pattern" || true); \
		if [ -n "$$pids" ]; then kill -9 $$pids 2>/dev/null || true; fi; \
	done

restart: run

smoke:
	./tests/gojo_smoke.sh

test-window:
	./tests/window_management_regression.sh

test-window-ui:
	./tests/window_power_view_regression.sh

test-window-focus:
	./tests/focused_window_provider_regression.sh

test-flux:
	./tests/flux_regression.sh

clean:
	rm -rf "$(DERIVED_DATA_PATH)"
