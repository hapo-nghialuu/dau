# Release macOS — Dấu

Pipeline phát hành bản macOS (`Dau.app`, ad-hoc signed, **không** notarization) thành zip tải được qua GitHub Release, kèm Homebrew cask.

## Tổng quan

| Mục | Giá trị |
|-----|---------|
| Build script | `scripts/build/macos.sh --adhoc` |
| App bundle | `platforms/macos/build/Release/Dau.app` |
| Release script | `scripts/release.sh` (mặc định `--arch universal`) |
| Artifact | `dist/Dau-<VERSION>.zip` + `dist/Dau-<VERSION>.zip.sha256` |
| Cask | `Casks/dau.rb` (bản nháp; formula chính thức đặt ở tap riêng `hapo-nghialuu/homebrew-tap`) |
| Chữ ký | Ad-hoc (`codesign -s -`), **chưa** Developer ID / notarize |

## Kiến trúc (arch)

Release script build app **universal** (cả `arm64` + `x86_64`) theo mặc định để một artifact chạy được trên cả Apple Silicon lẫn Intel. Truyền `--arch arm64` hoặc `--arch x86_64` khi cần bản single-arch.

| Flag | Ý nghĩa |
|------|---------|
| `universal` (mặc định) | Build cả 2 slice qua helper, verify app bằng `lipo -info` trước khi đóng gói |
| `arm64` | Chỉ Apple Silicon |
| `x86_64` | Chỉ Intel |

**Prerequisites cho bản universal** (`scripts/release.sh` guard fail sớm nếu thiếu):

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

`lipo` nằm trong Xcode command line tools — kiểm tra bằng `lipo -version`. Với `--skip-build`, guard bỏ qua kiểm tra rustup target (chỉ cần app đã build sẵn) nhưng **vẫn** verify slice của app bằng `lipo -info` trước khi đóng gói. Với `--dry-run`, guard bỏ qua cả `lipo` lẫn rustup targets — mode này không compile/verify gì, chỉ in kế hoạch.

## Build local (smoke)

Từ root repo:

```bash
./scripts/build/macos.sh --adhoc --version 0.1.0
```

Kết quả:

```text
platforms/macos/build/Release/Dau.app
```

Kiểm build:

```bash
test -d platforms/macos/build/Release/Dau.app && echo APP_OK
codesign --verify --deep --strict --verbose=2 platforms/macos/build/Release/Dau.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  platforms/macos/build/Release/Dau.app/Contents/Info.plist
```

Build này gọi `scripts/build/macos.sh --adhoc` (đúng contract): cargo release core → xcodebuild Release → codesign ad-hoc bằng entitlements production.

## Dry-run (không compile, không publish)

```bash
./scripts/release.sh 0.2.0 --dry-run
```

In ra kế hoạch:

```text
[release] ROOT=...
[release] APP_DIR=.../platforms/macos/build/Release/Dau.app
[release] ZIP_PATH=.../dist/Dau-0.2.0.zip
[release] Dry run complete — nothing compiled or published.
```

Cũng có thể xem kế hoạch build bên dưới:

```bash
./scripts/build/macos.sh --adhoc --version 0.2.0 --arch universal --dry-run
```

Dry-run theo kiến trúc:

```bash
./scripts/release.sh 0.2.0 --arch universal --dry-run   # default; build helper nhận --arch universal
./scripts/release.sh 0.2.0 --arch arm64 --dry-run
./scripts/release.sh 0.2.0 --arch x86_64 --dry-run
```

## Bước release (real run)

`scripts/release.sh VERSION` (không `--dry-run`) thực hiện:

1. **Guards** — branch `main`, tree sạch, `VERSION` semver hợp lệ, `--arch` hợp lệ, và (khi `--arch universal`) có `lipo` + đủ rustup targets.
2. **Build** — gọi `scripts/build/macos.sh --adhoc --version VERSION --arch ARCH` (mặc định `universal`).
3. **Verify** — kiểm tra app tồn tại, `CFBundleShortVersionString == VERSION`, và `lipo -info` xác nhận app executable có đủ slice mong đợi (universal: cả `arm64` lẫn `x86_64`).
4. **Package** — `ditto` → `dist/Dau-VERSION.zip`, rồi `shasum -a 256`.
5. **Publish** — `gh release create vVERSION` + upload zip & sha256, rồi cập nhật `sha256` trong cask local.

Script không tự `git push`; lệnh `gh release create vVERSION` sẽ tạo hoặc dùng tag release tương ứng sau khi source đã được commit trên `main`.

```bash
# 1. Bump version trong core/Cargo.toml (và MARKETING_VERSION khi cần) trên branch riêng
# 2. Merge lên main, pull, rồi:
./scripts/release.sh 0.2.0            # universal default — build + zip + sha + gh release
./scripts/release.sh 0.2.0 --arch x86_64   # Intel-only nếu cần
```

> `--skip-build` dùng lại app đã build sẵn (chỉ đóng gói + publish). Với `--arch universal`, nó bỏ qua kiểm tra rustup target nhưng **vẫn** verify app có đủ slice bằng `lipo -info` trước khi đóng gói — nhằm không package nhầm app single-arch thành bản universal.

## Cập nhật trong app (update checker)

App macOS tự kiểm tra bản mới qua GitHub Releases (`https://api.github.com/repos/hapo-nghialuu/dau/releases/latest`).

### Hành vi thực tế

- **Không bao giờ tự tải / thay thế app.** Chỉ mirror trạng thái vào menu bar + Settings:
  - Menu bar: row nhỏ "Có bản mới `<tag>` — xem trên GitHub" (ẩn khi không có bản mới / lỗi) + mục "Kiểm tra bản cập nhật…".
  - Settings → Cập nhật: nút "Kiểm tra…" + trạng thái.
- **So sánh semver** giữa `tag_name` và `CFBundleShortVersionString` (bundle version, ví dụ `0.1.3`). Chỉ hiện update khi `tag_name > version` hiện tại.
- **Throttle 24h** cho check tự động lúc launch (lưu mốc `dau.update.lastCheckedAt` trong `UserDefaults`); nút "Kiểm tra…" luôn check ngay.
- **Lỗi mạng / JSON hỏng → im lặng** (state `.failed`, không popup, không log nội dung).
- Hành động "xem trên GitHub" mở trang Release; còn hướng dẫn cập nhật Homebrew mở `docs/release-macos.md` trên GitHub. Không có key-path / UI blocking.

### Contract với pipeline release

`scripts/release.sh` tạo tag `v<semver>` (prefix `v` bắt buộc). Update checker parse tag qua `SemanticVersionParser` (bỏ prefix `v`, chấp nhận `X`, `X.Y`, `X.Y.Z`). Muốn checker nhận bản mới:

1. Bump `MARKETING_VERSION` trong `platforms/macos/Dau.xcodeproj/project.pbxproj` đúng semver (hiện `0.1.3`).
2. Release với `scripts/release.sh VERSION` (tạo `vVERSION` + zip + sha + upload GitHub Release).
3. Release không cần `draft`/`prerelease` — endpoint `/releases/latest` chỉ trả release mới nhất không phải draft.

Nếu tag không có prefix `v` hoặc không phải semver, checker bỏ qua (coi như không có bản mới).

## Cài trên Intel (x86_64)

Artifact universal (`Dau-<VERSION>.zip`) chạy được trên cả **Apple Silicon** lẫn **Intel Mac** — cùng một cask, cùng một zip, không cần bản riêng:

- **Apple Silicon** — chip tự chọn slice `arm64`.
- **Intel Mac** — chip tự chọn slice `x86_64`.

Khi cài qua Homebrew trên Intel:

```bash
brew tap hapo-nghialuu/tap
brew install --cask dau

> **⚠️ Lưu ý quan trọng:** Sau khi install hoặc upgrade version mới, **phải restart app** để event tap được khởi tạo lại:
> ```bash
> killall Dau
> open -a Dau
> ```
> Nếu không restart, app sẽ chạy nhưng không gõ được tiếng Việt. Chi tiết xem [Troubleshooting](troubleshooting-macos.md).
```

> Homebrew trên Intel Mac chạy Rosetta, cài app Intel/x86_64 bình thường. Nếu hệ thống 32-bit hoặc macOS quá cũ so với deployment target (hiện macOS 13+), app sẽ không chạy — đó là giới hạn deployment target, không phải lỗi cài đặt.

Để chắc app đã universal trước khi phát hành, chạy trên máy build:

```bash
lipo -info platforms/macos/build/Release/Dau.app/Contents/MacOS/Dau
# Kỳ vọng: Architectures in the fat file: ... are: x86_64 arm64
```

Release script đã verify điều này tự động trong bước **Verify** khi `--arch universal`.

## Homebrew cask

### Bản nháp trong repo này

`Casks/dau.rb` dùng URL:

```text
https://github.com/hapo-nghialuu/dau/releases/download/v#{version}/Dau-#{version}.zip
```

- App: `Dau.app`
- `sha256` để giá trị placeholder `0000…` trước khi có artifact đầu tiên.
- Sau một release thật, chạy `./scripts/release.sh 0.2.0` sẽ tự thay SHA trong cask.

### Formula chính thức ở tap riêng

Sao chép file cask này sang repo **homebrew-tap** riêng (tên chuẩn Homebrew: `homebrew-<tap>` → tap mặc định `hapo-nghialuu/<tap>`):

```bash
mkdir -p ~/homebrew-tap/Casks
cp Casks/dau.rb ~/homebrew-tap/Casks/dau.rb
cd ~/homebrew-tap && git init && git add -A
git commit -m "dau: add cask"
git remote add origin git@github.com:hapo-nghialuu/homebrew-tap.git
git push -u origin main
```

### Cài qua Homebrew

Lệnh đầy đủ (tap chưa được thêm):

```bash
brew install --cask hapo-nghialuu/tap/dau
```

Sau khi đã tap (`brew tap hapo-nghialuu/tap`), dùng lệnh ngắn:

```bash
brew tap hapo-nghialuu/tap
brew install --cask dau

> **⚠️ Lưu ý quan trọng:** Sau khi install hoặc upgrade version mới, **phải restart app** để event tap được khởi tạo lại:
> ```bash
> killall Dau
> open -a Dau
> ```
> Nếu không restart, app sẽ chạy nhưng không gõ được tiếng Việt. Chi tiết xem [Troubleshooting](troubleshooting-macos.md).
```

Cask gồm một `postflight` xoá cờ quarantine Gatekeeper (`xattr -dr com.apple.quarantine` trên `Dau.app`) ngay sau khi cài, nên app mở được ngay **không cần** Right-click → Open.

> ⚠️ **Phân biệt `postflight` với `brew trust`:** `brew trust --cask` là khái niệm **tin tưởng tap** của Homebrew, không liên quan Gatekeeper — nó không loại bỏ quarantine. Ngược lại, `postflight` bên trên xoá cờ **quarantine macOS** — và **không** đồng nghĩa với việc app được **notarize** hay được cấp **Accessibility / Post Event**. Người dùng vẫn phải tự cấp hai quyền đó trong *System Settings → Privacy & Security*.

## Ad-hoc & chưa notarize

- Bản build dùng `--adhoc`: ký bằng `-` (ad-hoc), **không** Developer ID, **không** notarize.
- **Cài qua Homebrew:** cask `postflight` chạy `xattr -dr com.apple.quarantine` trên `Dau.app`, xoá cờ quarantine macOS ngay khi cài xong → mở được ngay, **không bị** Gatekeeper chặn, cũng không cần Right-click → Open.
- **Cài bằng tay** (tải zip + unzip không qua cask): app còn dính cờ quarantine, có thể bị Gatekeeper chặn. Mở lần đầu:

```bash
open Dau.app
# hoặc: click chuột phải → Open
# hoặc bỏ quarantine: xattr -dr com.apple.quarantine <path Dau.app>
```

- Notarization (P4) sẽ cần `--sign` + `notarytool` — xem `scripts/build/macos.sh` (`--sign`, `--notarize`) và `platforms/macos/README.md`.

> **Lưu ý:** xoá quarantine (dù qua `postflight` hay `xattr` thủ công) **không** làm app trở thành đã notarize và **không** cấp **Accessibility** — quyền đó phải do người dùng bật thủ công (mục dưới).

## Quyền macOS (bắt buộc khi chạy)

Quyền TCC cần bật:

| API | Quyền | Mục đích |
|-----|-------|----------|
| `AXIsProcessTrusted` | **Accessibility** | Bắt phím / event tap |

Cách cấp: **System Settings → Privacy & Security → Accessibility** → bật đúng bản **Dấu** đang chạy. Với bản ad-hoc, sau mỗi lần rebuild / đổi path, macOS có thể coi binary là app khác → phải bỏ rồi thêm lại. Việc inject được kiểm tra bằng kết quả gửi sự kiện thật; nếu hệ thống từ chối, Dấu fail-open và cho phím gốc đi qua. Chi tiết: `platforms/macos/README.md`.

## Troubleshoot nhanh

| Triệu chứng | Xử lý |
|-------------|-------|
| `expected app bundle missing` | Chạy build thật trước, hoặc bỏ `--skip-build` |
| `bundle short version ... != release version` | Đồng bộ `VERSION` với `core/Cargo.toml` |
| `must run on 'main' branch` | `git checkout main` rồi chạy lại |
| `working tree must be clean` | Commit/stash thay đổi đang dở |
| `universal build requires missing rustup targets: ...` | `rustup target add aarch64-apple-darwin x86_64-apple-darwin` |
| `lipo not found ...` | Cài Xcode command line tools (`xcode-select --install`) |
| `expected universal app (arm64 + x86_64 slices) but got: ...` | App đang single-arch — rebuild đúng `--arch`, không dùng `--skip-build` với app cũ |
| Gatekeeper chặn app | Ad-hoc, chưa notarize — xem mục trên |
| `gh: command not found` | Cài GitHub CLI và `gh auth login` |

## Liên kết

- [scripts/release.sh](../scripts/release.sh)
- [scripts/build/macos.sh](../scripts/build/macos.sh)
- [platforms/macos/README.md](../platforms/macos/README.md)
- [Casks/dau.rb](../Casks/dau.rb)
