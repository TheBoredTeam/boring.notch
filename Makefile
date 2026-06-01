# boring.notch — build helpers

# Build the self-contained Pi sidecar binary (+ the runtime assets pi reads next
# to its executable) into boringNotch/Resources/. Requires `bun` on PATH.
#
# The binary and its assets are gitignored (the binary is ~69 MB); run this once
# after a fresh checkout, and again whenever sidecar/index.ts changes.
SIDECAR_PKG := sidecar/node_modules/@mariozechner/pi-coding-agent
RES := boringNotch/Resources

.PHONY: sidecar
sidecar:
	cd sidecar && bun install
	cd sidecar && bun build ./index.ts --compile --outfile ../$(RES)/pi-sidecar
	# Assets pi resolves next to the executable when run as a Bun binary.
	cp "$(SIDECAR_PKG)/package.json" "$(RES)/package.json"
	mkdir -p "$(RES)/theme" "$(RES)/export-html"
	cp "$(SIDECAR_PKG)/dist/modes/interactive/theme/"*.json "$(RES)/theme/"
	cp "$(SIDECAR_PKG)/dist/core/export-html/template.css" "$(RES)/export-html/"
	cp "$(SIDECAR_PKG)/dist/core/export-html/template.html" "$(RES)/export-html/"
	@echo "✅ pi-sidecar built at $(RES)/pi-sidecar"

.PHONY: clean-sidecar
clean-sidecar:
	rm -f "$(RES)/pi-sidecar" "$(RES)/package.json"
	rm -rf "$(RES)/theme" "$(RES)/export-html"
