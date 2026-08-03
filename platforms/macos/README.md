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
│   └── ui/                 # menu bar, onboarding, minimal settings (SET-06)
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

### 2. Accessibility + quyền gửi sự kiện (bắt buộc)

Hai cổng TCC **riêng** (macOS 10.15+):

| API | Ý nghĩa |
|-----|---------|
| `AXIsProcessTrusted` | Trợ năng — bắt phím / event tap |
| `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` | Gửi/tổng hợp sự kiện — inject chữ thay thế |

Triệu chứng thường gặp khi chỉ có AX: menu **“Accessibility: đã cấp · thiếu quyền gửi sự kiện…”**, onboarding **“Cần thêm quyền để gõ”**, badge **EN** (đúng — app chưa gõ được).

1. System Settings → **Privacy & Security** → **Accessibility** → bật **Dau** (hoặc **Dấu**).
2. Trong onboarding bấm **Cấp quyền…** để gọi `CGRequestPostEventAccess` (có thể hiện hộp thoại).
3. Nếu **vẫn** thiếu post-event (nút không còn hiện dialog):
   - Thoát Dấu hoàn toàn.
   - Accessibility → **xóa** Dấu khỏi danh sách → **thêm lại** binary đang chạy → bật.
   - Mở lại app → **Thử lại quyền…** / **Mở Cài đặt hệ thống…**.
4. **Mỗi lần rebuild ad-hoc / đổi path / đổi chữ ký**, TCC có thể coi binary là app khác — thường phải lặp bước 3. (Giả thuyết identity ad-hoc: **plausible** khi dev; không phải mọi máy đều tái hiện giống nhau.)

Script **không** ghi TCC database.

### 3. Menu bar tối thiểu

| Control | Việc |
|---------|------|
| **VI / EN** | Bật/tắt compose tiếng Việt |
| **Telex / VNI** | Kiểu gõ engine |
| Restart tap | Sau khi cấp AX hoặc tap bị disable |
| Quit | Thoát sạch |

## Contract gõ / delete (TG-01..04 + TG-00) — **hiện tại**

**Không** còn contract “Backspace xóa cả provisional word”. Behavior mong muốn và code hiện tại:

| Phím / tình huống | Contract |
|-------------------|----------|
| **Backspace (key 51)** khi đang compose | Xóa **đúng một** Unicode scalar đang hiển thị qua core `dau_backspace`; gõ tiếp tiếp tục compose trên buffer đã edit |
| **Backspace** buffer rỗng / idle | Pass-through (app nhận key gốc); không inject |
| **Forward Delete (key 117)** | Pass-through + **reset compose** (policy tường minh); **không** wipe provisional bằng inject Backspace |
| **Cmd/Ctrl/Option+Delete** + navigation | Boundary app-level: reset compose + forward shortcut/key |
| **EN / passthrough** | Fail-open: không kẹt callback; original key đi qua |
| **Menu VI/EN + tap status** | Phản ánh **trạng thái tap thật** (`eventTapRunning` / degraded/stopped), không báo “đang chạy” khi tap đã fail |
| **Badge "VI"** | Chỉ hiện khi **thật sự gõ được**: AX trusted **và** tap running **và** *quyền post-event đã cấp* **và** không bị input-source block **và** VI đang bật. Thiếu post-event → badge **EN** / `.setup` (không nói dối là đang gõ). Ý định VI/EN (toggle / ⌘⇧) vẫn hiện trong **tooltip**, **a11y label**, **subtitle menu** (`ý định VI` / `ý định EN`) và công tắc header. Onboarding: mỗi lần bấm CTA có thể gọi lại `CGRequestPostEventAccess`; sau lần 1 vẫn deny thì copy hướng dẫn xóa/thêm lại Accessibility |

### TG-00 fail-open (code đã land; live soak **chưa** chạy)

- Keyboard **không được freeze** toàn hệ thống vì Dấu.
- Nếu callback/dependency kẹt hoặc health fail: tap có thể **degraded/stopped** để macOS pass phím (fail-open) — đây là degraded OK, **không** phải full product PASS.
- Quit Dấu không còn là cách “cứu” bàn phím bắt buộc sau idle/sleep (mục tiêu code); **chưa** có biên nhận soak 30 phút / sleep-wake trên máy user.

Unit / XCTest **xanh không thay** smoke tay. Biên nhận unit: xem `docs/vietnamese-typing-corpus-results.md` và plan TG-06.

### Injection method & AX role (gap-close 2026-08-01)

- **AX role production:** `AppContextResolver` default dùng `AXFocusedRoleProvider` (bounded, ngoài hot path; cache khi focus change). `StubAXRoleProvider` chỉ là test seam, không tham gia runtime.
- **Role fallback:** `InjectionProfileResolver` áp `roleMethods` khi không có user/shipped bundle profile: `.terminal`→`backspaceFast`, `.editor`→`charByChar`, `.textField`→`backspaceFast`, `.comboBox`→`selection`, `.addressBar`→`emptyCharPrefix`, `.other`→`backspaceFast`.
- **`selection`** (Shift+Left select rồi replace; text rỗng dùng Backspace thật) và **`emptyCharPrefix`** (post U+202F break autocomplete, xoá `backspace+1`, chèn text) đã **implemented** trong `TextInjector` (`planSelection` / `planEmptyCharPrefix`) — có unit test command ordering/failure. Cả hai thêm **bounded one-time 1ms zero-delay floor** (Gõ Nhanh parity, `well under 12ms budget`): `selection` chờ 1000us một lần trước text khi `settleUs==0`; `emptyCharPrefix` chờ 1000us một lần sau prefix khi `backspaceUs==0` — không per-scalar/per-backspace; user delay > 0 giữ nguyên giá trị.
- **`syncProxy` vẫn là stub fallback** → `backspaceFast` (declared-only; resolve/inject fallback explicit, log một lần). `axDirect` thật, fallback synthetic khi AX fail.

### 4. Gợi ý corpus smoke (user tự ghi PASS/FAIL)

| App | Gõ | Kỳ vọng |
|-----|-----|---------|
| TextEdit | `tieengs` + Space | `tiếng ` |
| TextEdit | `Vieejt` + Space | `Việt ` |
| TextEdit | gõ dở + Esc | restore raw |
| Terminal.app | cùng Telex | không nuốt/dính nghiêm trọng |
| IDE terminal / Claude Code | gõ nhanh | ghi riêng nếu fail |

Tắt tạm OpenKey / Gõ Nhanh / IME khác khi so sánh.

### 4b. Manual matrix — Backspace / Forward Delete + paste/media + delivery

**Trạng thái (TG-06):** matrix dưới đây **bắt buộc user chạy tay**. **Chưa claim PASS** — chưa có biên nhận live app trên TextEdit / Terminal / browser / Electron.

Ghi app / version / method / raw keys / expected / actual / PASS|FAIL.

Chạy tối thiểu trên **TextEdit**, **Terminal.app**, một **browser contenteditable** (Safari/Chromium), và **Electron/chat**.

| # | Bối cảnh | Thao tác | Kỳ vọng |
|---|----------|----------|---------|
| D1 | Telex compose | `tieengs` → Backspace → `g` → Space | `tiếng ` **một lần** (BS chỉ bỏ `g` → `tiến`, gõ lại `g` khôi phục) |
| D2 | VNI compose | `tie6ng1` → Backspace → `g` → Space | Tương tự D1 → `tiếng ` một lần |
| D2b | Telex | `dduaw` → Backspace → `a` | `đưa` → `đư` → `đưa` |
| D2c | English | `delete` → Backspace → `e` | `delete` → `delet` → `delete` |
| D3 | Sau commit | Gõ xong từ + Space → Backspace | App xoá **một** ký tự (Space hoặc chữ cuối theo caret); **không** inject word cũ |
| D4 | Idle (không compose) | Backspace / Forward Delete | Pass-through bình thường của app |
| D4b | Đang compose | Forward Delete | Pass-through + reset compose; **không** wipe cả từ bằng inject |
| D5 | Đổi method | Backspace hết buffer → chuyển Telex↔VNI → gõ từ mới | Word mới đúng method; không dính provisional cũ |
| E1 | English plain | `delete` + Space lặp 100 (TextEdit + Terminal + browser + Electron) | `delete ` đúng một lần/vòng; 0 mất/dup |
| E2 | Telex/VNI common | `tieengs` / `tie6ng1` / `dduaw` lặp theo profile | 0 mất/dup/break sai |
| P1 | Idle | Cmd+V paste **plain text** | Dấu không nuốt shortcut; text dán đúng; gõ `tieengs` sau đó sạch |
| P2 | Đang compose | Gõ dở → Cmd+V paste **plain text** | Shortcut pass-through; compose reset; sau paste gõ từ mới **không** dính/lặp |
| P3 | Idle | Cmd+V paste **image** hoặc **GIF** | Không nuốt Cmd+V; không inject ký tự lạ; word kế tiếp sạch |
| P4 | Đang compose | Gõ dở → paste **image/GIF** | Giống P3 + state compose không “dính” vào media |
| S7a | EN + VI | Idle 30 phút (màn hình sáng) → gõ `delete ` + `tieengs` | Không freeze; không cần quit Dấu |
| S7b | EN + VI | Display sleep/wake, system sleep/wake, lock/unlock ×5 | Sau mỗi vòng gõ được ngay; UI VI/EN khớp tap thật |

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

## Settings window (SET-06)

Menu **Cài đặt…** (`⌘,`) mở cửa sổ **700×480**, sidebar + content:

| Sidebar | Nội dung |
|---------|----------|
| **Cài đặt** | Bộ gõ (VI/EN, Telex/VNI), phím tắt bật/tắt (recorder), quy tắc (auto-restore, auto-cap), Accessibility status, **Mở khi đăng nhập** (SET-06), **Kiểm tra cập nhật** (UPDATE-01) |
| **Nâng cao** | App phía trước + resolved profile; preset delay Nhanh/Vừa/Chậm → user override |
| **Giới thiệu** | Logo, version/core, privacy, link GitHub |

Prefs: `dau.settings.{typingEnabled,engineMethod,autoRestore,autoCapitalize,toggleHotkey}` (+ `launchAtLoginDesired`, `dau.update.lastCheckedAt`).

**Mở khi đăng nhập:** toggle qua `SMAppService.mainApp` (macOS 13+). Trạng thái hiển thị mirror status thật từ hệ thống (`.enabled` / `.disabled` / `.notFound` / `.requiresApproval` / `.error`), không phải UserDefaults guess. Khi `requiresApproval` → nút "Mở Login Items…" mở System Settings. Toggle lỗi → hiển thị lỗi, giữ nguyên trạng thái thật.

**Kiểm tra cập nhật:** async, đọc `https://api.github.com/repos/hapo-nghialuu/dau/releases/latest`, so sánh semver với `CFBundleShortVersionString`. Throttle 24h lúc launch; nút "Kiểm tra…" / menu "Kiểm tra bản cập nhật…" check ngay. Không bao giờ tự tải/thay app. Lỗi mạng/parse → im lặng. Chi tiết: `docs/release-macos.md`.

**Phím tắt bật/tắt (VI/EN):** mặc định `⇧⌘E` (Cmd+Shift+E). Cấu hình trong **Cài đặt → Phím tắt → Đổi…**. Hai dạng hợp lệ: phím + ≥1 trong ⌘/⌃/⌥, hoặc **chord chỉ-modifier ≥2 phím** (ví dụ `⌘⇧`).

Hai đường đăng ký khác nhau, không thể gộp:

| Dạng | Cơ chế | Ghi chú |
|------|--------|---------|
| Phím + modifier (`⇧⌘E`) | Carbon `RegisterEventHotKey` | Carbon không đăng ký được chord chỉ-modifier |
| Chỉ modifier (`⌘⇧`) | `CGEventTap` `.listenOnly` trên `flagsChanged` | Cần Accessibility để tạo tap |

Đăng ký được **thử lại** ở các đường phục hồi (`attemptStartTap` khi tap lên, `restartTap`, sau wake) khi lần trước thất bại — cấp Accessibility muộn không còn làm phím tắt chết vĩnh viễn. Retry chỉ chạy khi chưa đăng ký thành công, không tear-down tap đang chạy tốt.

Menu header + tooltip hiển thị tổ hợp hiện tại. `NSMenuItem` toggle **cố ý** để `keyEquivalent: ""` — tránh double-toggle với đường global ở trên.

Không gồm: full inject matrix UI, conflict matrix với system shortcuts, tự tải/replace app (update checker chỉ thông báo + mở trang).

Mở: menu bar → **Cài đặt…** hoặc **Giới thiệu** (About page).

## Out of scope (sau smoke)

- Full P3 inject matrix — `selection`/`emptyCharPrefix`/`axDirect` đã implemented; chỉ còn **`syncProxy`** (game/Electron strict-order) là stub fallback
- Advanced settings / profile editor UI
- Developer ID + notarize (P4)
- Core / Linux product changes

## Receipt build / regression (máy dev, tham chiếu)

| Field | Value |
|-------|--------|
| Product HEAD (TG-05) | `7523970` |
| TG-00 / TG-01..04 | `d678cd4` / `5eb43fc` |
| `cargo fmt --check` (core) | PASS (2026-07-25; sau `cargo fmt` formatting-only) |
| `cargo test --manifest-path core/Cargo.toml` | **126** lib unit PASS (re-run 2026-08-01) |
| English gate | **188** words × **8** breaks raw PASS; **10** intentional VN collisions stay VN |
| Top-2000 | Telex **2000** PASS + **0** SKIP-KNOWN + **0** FAIL; VNI tương đương |
| `xcodebuild test … platform=macOS` | **293** tests PASS (re-run 2026-08-01, 0 failures) |
| Live smoke / idle soak | **user — chưa chạy; không claim PASS** |
| Chi tiết | `docs/vietnamese-typing-corpus-results.md`, `plans/typing-gaps-dau-vs-gonhanh.md` |
