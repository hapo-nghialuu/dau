# Dấu — macOS bridge

CGEventTap + Swift menu-bar app over the shared `dau-core` C ABI.

## Prerequisites

| Tool | Notes |
|------|--------|
| macOS 13+ | Deployment target hiện tại |
| Xcode 15+ | `xcodebuild`, macOS SDK |
| Rust / cargo | Build `libdau_core.a` |
| Accessibility (TCC) | User grant khi chạy — **không** tự cấp bằng script |

Worktree ví dụ:

```bash
cd /Users/nghialuutrung/.herdr/worktrees/dau/feature-macos-start
```

## Layout

```text
platforms/macos/
├── Dau.xcodeproj/          # schemes: Dau, DauTests
├── Sources/
│   ├── app/                # @main, AppDelegate, AppState
│   ├── session/            # TypingSession (map sync / inject async)
│   ├── bridge/             # DauCoreBridge, mapper, MacKeyPipeline
│   ├── config/             # injection profiles + resolver
│   ├── input/              # EventTap, classifier, focus, input-source
│   ├── output/             # TextInjector, methods, AX helpers
│   └── ui/                 # menu bar, Accessibility onboarding
├── Support/dau-bridging-header.h
├── Resources/
│   ├── Info.plist, entitlements, profiles.toml
│   └── Assets.xcassets/    # AppIcon, AppLogo, MenuBar{Setup,Active,Inactive}
├── Tests/                  # unit tests (no live system-wide smoke)
└── build/                  # gitignored — lib, Debug/Release app, DerivedData
```

### Brand assets (ASSET-01)

| Asset name | Dùng cho |
|------------|----------|
| `AppIcon` | Finder / About / Dock khi activation policy regular |
| `AppLogo` | Onboarding / UI brand (color) |
| `MenuBarSetup` / `MenuBarActive` / `MenuBarInactive` | Status item template images (MENU-02 wire) |

Nguồn master: `assets/logo.svg` (render vector → slot; không upscale PNG nhỏ). `LSUIElement=true` giữ app accessory (không Dock mặc định).

## Build chuẩn (dev smoke)

Từ **root repo / worktree** (không `cd` vào `platforms/macos` trước khi gọi script):

```bash
./scripts/build/macos.sh --debug
```

Script sẽ:

1. `cargo build --release` cho `dau-core` → `platforms/macos/build/lib/libdau_core.a`
2. `xcodebuild` scheme **Dau**, configuration **Debug**
3. Copy / đặt artifact tại path dưới

### Artifact chính

| Mục | Path (relative root) |
|-----|----------------------|
| **App smoke** | `platforms/macos/build/Debug/Dau.app` |
| Static lib | `platforms/macos/build/lib/libdau_core.a` |
| DerivedData (xcode) | `platforms/macos/build/DerivedData/…` (nếu script dùng) |

Absolute (worktree hiện tại):

```text
/Users/nghialuutrung/.herdr/worktrees/dau/feature-macos-start/platforms/macos/build/Debug/Dau.app
```

### Kiểm build

```bash
test -d platforms/macos/build/Debug/Dau.app && echo APP_OK
codesign --verify --verbose=2 platforms/macos/build/Debug/Dau.app
```

### Fallback (khi script lỗi)

```bash
cargo build --manifest-path core/Cargo.toml --release
# copy/link lib theo README script nếu cần, rồi:
xcodebuild \
  -project platforms/macos/Dau.xcodeproj \
  -scheme Dau \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath platforms/macos/build/DerivedData \
  build
```

App fallback:

```text
platforms/macos/build/DerivedData/Build/Products/Debug/Dau.app
```

### Unit test (không thay smoke tay)

```bash
xcodebuild test \
  -project platforms/macos/Dau.xcodeproj \
  -scheme Dau \
  -destination 'platform=macOS'
```

### Mode khác

```bash
./scripts/build/macos.sh --adhoc    # Release-ish ad-hoc sign (xem script)
./scripts/build/macos.sh --help     # full flags
```

Public **Developer ID + notarize** = P4 — cần cert; không bắt buộc smoke local.

## Chuẩn bị app để smoke (user)

### 1. Mở app

```bash
open platforms/macos/build/Debug/Dau.app
```

- App **menu bar** (accessory / không Dock).
- Không thấy icon: kiểm tra menu bar overflow, hoặc Activity Monitor process **Dau**.

Chạy foreground (log stderr `[dau] …`):

```bash
platforms/macos/build/Debug/Dau.app/Contents/MacOS/Dau
```

### 2. Accessibility (bắt buộc)

1. System Settings → **Privacy & Security** → **Accessibility** → bật **Dau**.
2. Hoặc follow onboarding trong app (prompt TCC).
3. Menu bar: restart tap / đợi trạng thái trusted (README cũ: `Dấu?` cho đến khi OK).
4. **Mỗi lần đổi path binary / rebuild** có thể phải xóa Dau khỏi list Accessibility rồi thêm lại.

Script **không** ghi TCC database.

### 3. Menu bar tối thiểu

| Control | Việc |
|---------|------|
| **VI / EN** | Bật/tắt compose tiếng Việt |
| **Telex / VNI** | Kiểu gõ engine |
| Restart tap | Sau khi cấp AX hoặc tap bị disable |
| Quit | Thoát sạch |

### 4. Gợi ý corpus smoke (user tự ghi PASS/FAIL)

| App | Gõ | Kỳ vọng |
|-----|-----|---------|
| TextEdit | `tieengs` + Space | `tiếng ` |
| TextEdit | `Vieejt` + Space | `Việt ` |
| TextEdit | gõ dở + Esc | restore raw |
| Terminal.app | cùng Telex | không nuốt/dính nghiêm trọng |
| IDE terminal / Claude Code | gõ nhanh | ghi riêng nếu fail |

Tắt tạm OpenKey / Gõ Nhanh / IME khác khi so sánh.

### 4b. Manual matrix — Delete/retype + paste/media (DELETE-05)

Unit tests **không** thay smoke tay. P0 contract hiện tại: **Backspace/Delete khi đang compose = wipe toàn bộ provisional** (không phải xoá từng ký tự). Ghi app / version / method / raw keys / expected / actual / PASS|FAIL.

Chạy tối thiểu trên **TextEdit**, **Terminal.app**, một **browser contenteditable** (Safari/Chromium), và **chat** nơi đã smoke Dấu.

| # | Bối cảnh | Thao tác | Kỳ vọng |
|---|----------|----------|---------|
| D1 | Telex compose | `tieengs` → Backspace → gõ lại `tieengs` → Space | Wipe hết provisional; màn hình còn `tiếng ` **một lần** |
| D2 | VNI compose | `tie6ng1` → Backspace → gõ lại → Space | Tương tự D1 → `tiếng ` một lần |
| D3 | Sau commit | Gõ xong từ + Space → Backspace | App xoá **một** ký tự (Space hoặc chữ cuối theo caret); **không** inject word cũ |
| D4 | Idle (không compose) | Backspace / Forward Delete | Pass-through bình thường của app |
| D5 | Đổi method | Wipe → chuyển Telex↔VNI → gõ từ mới | Word mới đúng method; không dính provisional cũ |
| P1 | Idle | Cmd+V paste **plain text** | Dấu không nuốt shortcut; text dán đúng; gõ `tieengs` sau đó sạch |
| P2 | Đang compose | Gõ dở → Cmd+V paste **plain text** | Shortcut pass-through; compose reset; sau paste gõ từ mới **không** dính/lặp |
| P3 | Idle | Cmd+V paste **image** hoặc **GIF** | Không nuốt Cmd+V; không inject ký tự lạ; word kế tiếp sạch |
| P4 | Đang compose | Gõ dở → paste **image/GIF** | Giống P3 + state compose không “dính” vào media |

Nếu whole-wipe (D1/D2) không chấp nhận được khi smoke, ghi FAIL + expected UX → mở package P1 (per-character Backspace), **không** đổi semantics trong P0.

### 5. Rebuild → re-test

```bash
./scripts/build/macos.sh --debug
# re-check Accessibility nếu binary path đổi
open platforms/macos/build/Debug/Dau.app
```

## Runtime path (kiến trúc)

```text
CGEventTap → KeyClassifier → profile cache
  → TypingSession (queue.sync map → queue.async inject)
  → MacKeyPipeline / dau-core → BridgeResult
  → TextInjector (backspace + Unicode, synthetic marker)
```

Toggle EN, focus change, tap restart, input source non-Latin: clear compose.

Quyết định kiến trúc: [docs/project-anchor.md](../../docs/project-anchor.md) §4.1 + §8.6.

## Entitlements

| File | Notes |
|------|--------|
| `Dau.entitlements.dev` | no sandbox; `get-task-allow` (Debug) |
| `Dau.entitlements.production` | no sandbox; no `get-task-allow` |

Accessibility = **TCC user grant**, không phải entitlement.

## Bundle id (placeholder)

`io.github.hapo-nghialuu.dau` — đổi chỉ khi release-owner OK (TCC re-auth).

## Out of scope (sau smoke)

- Full P3 inject matrix (selection / empty prefix / syncProxy / axDirect product)
- Advanced settings / profile editor UI
- Developer ID + notarize (P4)
- Core / Linux product changes

## Receipt build (máy dev, tham chiếu)

Lần chuẩn bị smoke (worktree `feature-macos-start`):

| Field | Value |
|-------|--------|
| Command | `./scripts/build/macos.sh --debug` → exit **0** |
| App | `platforms/macos/build/Debug/Dau.app` |
| codesign --verify | OK |
| HEAD | `ca4189c` (tại thời điểm build) |
| arch | arm64 |
| Smoke runtime | **user** — chưa claim PASS |
