.PHONY: test lint fmt build-core header build-addon

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

# Fcitx5 addon (requires fcitx5-dev + cmake on Linux).
build-addon:
	cd platforms/linux && cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
