# Phát triển Dấu

Tài liệu cho người đóng góp: kiến trúc, build/test, quy ước, cấu trúc thư mục.  
Phiên bản sản phẩm: **0.1.0** · License: **MIT** · Repo: https://github.com/hapo-nghialuu/dau

## Kiến trúc

```
┌─────────────────────────────────────────────────────────────┐
│  Fcitx5 (Linux)                                             │
│    dau_addon / dau_engine  →  Fcitx5Sink (preedit/commit)   │
│              │                                              │
│    TypingController  ←→  StrategyResolver                    │
│              │           (preedit vs backspace, per context)│
│         RustBridge (C ABI)                                  │
└──────────────┼──────────────────────────────────────────────┘
               │  dau_core.h / libdau_core.a
┌──────────────▼──────────────────────────────────────────────┐
│  core/  (Rust crate: dau-core)                              │
│    engine: Telex, VNI, tone, buffer, UX (auto-restore, …)   │
│    config (TOML) · ffi (C ABI ổn định)                      │
└─────────────────────────────────────────────────────────────┘
```

### Lớp chính

| Thành phần | Vai trò |
|------------|---------|
| **dau-core** | Engine gõ thuần, không phụ thuộc GUI/IME |
| **FFI** (`ffi.rs` → `dau_core.h`) | C ABI cho bridge nền tảng |
| **RustBridge** | Wrapper C++ gọi core |
| **TypingController** | Máy trạng thái gõ testable (không link Fcitx5) |
| **StrategyResolver** | Chọn chiến lược output (preedit / backspace, …) |
| **Fcitx5Sink / dau_engine** | Tích hợp InputContext Fcitx5 |

Logic gõ tách khỏi Fcitx5 để unit test bằng C++ (`ctest`) và Rust (`cargo test`) độc lập.

### Phạm vi v1

- **Linux + Fcitx5** — fully supported  
- **macOS** — roadmap (cùng core, bridge khác)  
- Không đụng Windows trong v1

## Cấu trúc thư mục

```
dau/
├── core/                 # Rust: dau-core 0.1.0
│   ├── src/              # engine, ffi, config
│   ├── include/dau_core.h
│   └── Cargo.toml
├── platforms/linux/      # Fcitx5 addon
│   ├── src/              # C++ bridge + typing logic
│   ├── data/             # dau.conf, dau-addon.conf, icons
│   ├── tests/            # typing_controller, strategy_resolver
│   └── CMakeLists.txt
├── scripts/              # build / install / uninstall / check-metadata
├── docs/                 # tài liệu sản phẩm + neo
├── assets/               # logo, icon nguồn
├── Makefile
└── README.md
```

Tài liệu neo (không sửa nhẹ nhàng): `docs/project-anchor.md`, `docs/design-per-app-typing.md`.

## Build

### Core (mọi OS có Rust)

```bash
cd core && cargo build --release
# hoặc
make build-core
```

Header C sinh qua `build.rs` / cbindgen → `core/include/dau_core.h`.

### Addon Fcitx5 (Linux)

```bash
./scripts/build.sh          # core release + cmake addon
./scripts/build.sh --debug  # debug
make build-addon            # alias script
```

Trên macOS / thiếu fcitx5-dev: script chỉ build core và in cảnh báo (exit 0).

### Cài / gỡ

```bash
./scripts/install.sh              # ~/.local
./scripts/install.sh --system     # /usr + sudo
./scripts/uninstall.sh
```

Chi tiết: [install-linux.md](install-linux.md).

## Test

### Rust (core)

```bash
cd core && cargo test
# hoặc
make test
```

### C++ unit tests (typing + strategy, không cần runtime Fcitx5)

Trên Linux sau khi configure CMake:

```bash
cd platforms/linux
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

Các test binary:

- `dau_typing_test` — TypingController + mock sink  
- `dau_strategy_resolver_test` — StrategyResolver  

### Metadata

```bash
./scripts/check-metadata.sh
# hoặc
make check-metadata
```

### Lint core

```bash
make lint   # cargo fmt --check && cargo clippy -D warnings
```

## Quy ước commit

Dùng [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(core): add VNI double-tone restore
fix(linux): preedit clear on focus out
docs: install-linux troubleshooting
chore(scripts): portable dry-run on macOS
```

Gợi ý scope: `core`, `linux`, `ffi`, `docs`, `scripts`, `ci`.

- Một commit = một ý thay đổi rõ ràng  
- Không commit secret (`.env`, key)  
- AI attribution: chỉ khi project/user yêu cầu (footer), không nhét vào subject  

## Metadata sản phẩm (đồng nhất)

| Trường | Giá trị |
|--------|---------|
| Tên hiển thị | Dấu |
| ID | `dau` |
| Version | `0.1.0` |
| License | MIT |
| Repo | https://github.com/hapo-nghialuu/dau |

Nguồn kiểm tra: `core/Cargo.toml`, `platforms/linux/CMakeLists.txt`, `data/*.conf`, `README.md`, SPDX trên `platforms/linux/src/*`.

## CI

Workflow GitHub Actions (`.github/workflows/ci.yml`) chạy test core và build addon trên Linux. Badge trên [README](../README.md).

## Liên kết

- [README](../README.md)
- [Cài đặt Linux](install-linux.md)
- [Project anchor](project-anchor.md)
