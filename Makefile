.PHONY: test lint fmt build-core header build-addon install uninstall check-metadata help

help:
	@echo "Dấu — common targets"
	@echo "  make test            Run Rust core tests"
	@echo "  make lint            cargo fmt --check + clippy"
	@echo "  make build-core      cargo build --release (core)"
	@echo "  make build-addon     ./scripts/build.sh (core + addon)"
	@echo "  make install         ./scripts/install.sh (user-local)"
	@echo "  make uninstall       ./scripts/uninstall.sh"
	@echo "  make check-metadata  ./scripts/check-metadata.sh"
	@echo "  make header          Ensure core/include/dau_core.h exists"

test:
	cd core && cargo test

lint:
	cd core && cargo fmt --check && cargo clippy -- -D warnings

fmt:
	cd core && cargo fmt

build-core:
	cd core && cargo build --release

# Generate C header via cbindgen (build.rs → core/include/dau_core.h).
header:
	cd core && cargo build
	@test -f core/include/dau_core.h && echo "HEADER_OK: core/include/dau_core.h"

# Build core + Fcitx5 addon via packaging script (Linux; macOS = core only).
build-addon:
	./scripts/build.sh

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

check-metadata:
	./scripts/check-metadata.sh
