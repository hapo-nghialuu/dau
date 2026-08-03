# Dấu

<p align="center">
  <img src="assets/logo.svg" alt="Dấu logo" width="128" height="128">
</p>

<p align="center">
  <strong>Bộ gõ tiếng Việt cho Linux và macOS</strong> — nhanh, riêng tư, terminal &amp; AI CLI first-class.
</p>

<p align="center">
  <a href="https://github.com/hapo-nghialuu/dau/actions/workflows/ci.yml"><img src="https://github.com/hapo-nghialuu/dau/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/version-0.1.3-blue" alt="version 0.1.3">
  <img src="https://img.shields.io/badge/license-MIT%20%2B%20BSD--3--Clause-green" alt="MIT + BSD-3-Clause">
  <img src="https://img.shields.io/badge/platform-Linux%20(Fcitx5)%20%7C%20macOS-orange" alt="Linux Fcitx5 and macOS">
</p>

**Dấu** (`dau`) là bộ gõ tiếng Việt mã nguồn mở, offline 100%, dùng **Rust core** với bridge Fcitx5 trên Linux và native event tap trên macOS. Phiên bản **0.1.3**.

> English: *Vietnamese input method for Linux — fast, private, terminal & AI-CLI first-class.*

## Tính năng chính

- **Telex & VNI** — hai kiểu gõ quen thuộc
- **Terminal & AI CLI first-class** — mượt trong terminal và các AI CLI (Claude Code, Codex, …)
- **Auto-restore** — tự khôi phục từ tiếng Anh khi gõ nhầm (Space / ESC)
- **Gõ tắt** — mở rộng từ viết tắt theo cấu hình
- **Privacy** — không telemetry, không thu thập dữ liệu, chạy offline

## Cài đặt nhanh (Linux)

Yêu cầu: Fcitx5, Rust (`cargo`), CMake, g++, gói dev Fcitx5.

```bash
git clone https://github.com/hapo-nghialuu/dau.git
cd dau
./scripts/build.sh && ./scripts/install.sh
```

Sau đó mở `fcitx5-configtool`, thêm phương thức gõ **Dấu**, rồi `fcitx5 -r`.

Cài system-wide: `./scripts/install.sh --system` (cần sudo).  
Gỡ cài: `./scripts/uninstall.sh` (hoặc `--system`).

Chi tiết: **[docs/install-linux.md](docs/install-linux.md)**.

## Tài liệu

| Tài liệu | Nội dung |
|----------|----------|
| [Cài đặt Linux](docs/install-linux.md) | Yêu cầu, build, kích hoạt Fcitx5, gỡ cài, troubleshoot |
| [Phát triển](docs/development.md) | Kiến trúc, build/test, quy ước commit, cấu trúc repo |
| [Neo dự án](docs/project-anchor.md) | Tầm nhìn & quyết định kiến trúc cấp cao |
| [Release macOS](docs/release-macos.md) | Build local, dry-run, release, Homebrew cask, quyền macOS |

## Kiến trúc (tóm tắt)

```
Linux: Phím → Fcitx5 addon (C++) → FFI → dau-core (Rust) → preedit / commit
macOS: Phím → Accessibility/Event Tap → Swift bridge → FFI → dau-core (Rust)
```

- `core/` — engine Telex/VNI, config, C ABI (`dau_core.h`)
- `platforms/linux/` — bridge Fcitx5, `typing_controller`, `strategy_resolver`
- Một core dùng chung; mỗi nền tảng có bridge riêng

Xem [docs/development.md](docs/development.md).

## Phát triển nhanh

```bash
make test              # cargo test (core)
make build-addon       # ./scripts/build.sh
make check-metadata    # đồng bộ version / license / repo
```

## Roadmap

| Nền tảng | Trạng thái |
|----------|------------|
| **Linux (Fcitx5)** | v0.1.3 — hỗ trợ |
| **macOS** | Beta kỹ thuật — bridge native, cùng core Rust |
| Windows | Ngoài phạm vi v1 |

## License

- **MIT** — [LICENSE](LICENSE) — Copyright (c) 2026 Dấu Contributors (primary).
- **BSD-3-Clause** — portions of the host-facing FFI **display-delta** contract are
  derived from [Gõ Nhanh](https://github.com/gonhanh/gonhanh)
  (Copyright (c) 2025, Gõ Nhanh Contributors). Full text and file list: **[NOTICE](NOTICE)**.

Repo: [https://github.com/hapo-nghialuu/dau](https://github.com/hapo-nghialuu/dau)
