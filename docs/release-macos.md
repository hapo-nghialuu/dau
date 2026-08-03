# Release macOS — Dấu

Pipeline phát hành bản macOS (`Dau.app`, ad-hoc signed, **không** notarization) thành zip tải được qua GitHub Release, kèm Homebrew cask.

## Tổng quan

| Mục | Giá trị |
|-----|---------|
| Build script | `scripts/build/macos.sh --adhoc` |
| App bundle | `platforms/macos/build/Release/Dau.app` |
| Release script | `scripts/release.sh` |
| Artifact | `dist/Dau-<VERSION>.zip` + `dist/Dau-<VERSION>.zip.sha256` |
| Cask | `Casks/dau.rb` (bản nháp; formula chính thức đặt ở tap riêng `hapo-nghialuu/homebrew-tap`) |
| Chữ ký | Ad-hoc (`codesign -s -`), **chưa** Developer ID / notarize |

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
./scripts/build/macos.sh --adhoc --version 0.2.0 --dry-run
```

## Bước release (real run)

`scripts/release.sh VERSION` (không `--dry-run`) thực hiện:

1. **Guards** — branch `main`, tree sạch, `VERSION` semver hợp lệ.
2. **Build** — gọi `scripts/build/macos.sh --adhoc --version VERSION`.
3. **Verify** — kiểm tra app tồn tại, `CFBundleShortVersionString == VERSION`.
4. **Package** — `ditto` → `dist/Dau-VERSION.zip`, rồi `shasum -a 256`.
5. **Publish** — `gh release create vVERSION` + upload zip & sha256, rồi cập nhật `sha256` trong cask local.

Script không tự `git push`; lệnh `gh release create vVERSION` sẽ tạo hoặc dùng tag release tương ứng sau khi source đã được commit trên `main`.

```bash
# 1. Bump version trong core/Cargo.toml (và MARKTETING_VERSION khi cần) trên branch riêng
# 2. Merge lên main, pull, rồi:
./scripts/release.sh 0.2.0            # build + zip + sha + gh release
```

> `--skip-build` dùng lại app đã build sẵn (chỉ đóng gói + publish).

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
```

## Ad-hoc & chưa notarize

- Bản build dùng `--adhoc`: ký bằng `-` (ad-hoc), **không** Developer ID, **không** notarize.
- macOS Gatekeeper sẽ chặn/ hỏi khi mở. Mở lần đầu:

```bash
open "$(brew --caskroom)/dau"/$(ls "$(brew --caskroom)/dau")/Dau.app
# hoặc: click chuột phải → Open
# hoặc bỏ quarantine: xattr -dr com.apple.quarantine <path Dau.app>
```

- Notarization (P4) sẽ cần `--sign` + `notarytool` — xem `scripts/build/macos.sh` (`--sign`, `--notarize`) và `platforms/macos/README.md`.

## Quyền macOS (bắt buộc khi chạy)

Hai cổng TCC riêng:

| API | Quyền | Mục đích |
|-----|-------|----------|
| `AXIsProcessTrusted` | **Accessibility** | Bắt phím / event tap |
| `CGPreflightPostEventAccess` | **Input Monitoring** (post-event) | Gửi/tổng hợp sự kiện, inject chữ |

Cách cấp: **System Settings → Privacy & Security → Accessibility / Input Monitoring** → bật **Dấu** (Dau). Sau mỗi lần rebuild ad-hoc / đổi path, macOS có thể coi binary là app khác → phải bỏ rồi thêm lại. Chi tiết: `platforms/macos/README.md`.

## Troubleshoot nhanh

| Triệu chứng | Xử lý |
|-------------|-------|
| `expected app bundle missing` | Chạy build thật trước, hoặc bỏ `--skip-build` |
| `bundle short version ... != release version` | Đồng bộ `VERSION` với `core/Cargo.toml` |
| `must run on 'main' branch` | `git checkout main` rồi chạy lại |
| `working tree must be clean` | Commit/stash thay đổi đang dở |
| Gatekeeper chặn app | Ad-hoc, chưa notarize — xem mục trên |
| `gh: command not found` | Cài GitHub CLI và `gh auth login` |

## Liên kết

- [scripts/release.sh](../scripts/release.sh)
- [scripts/build/macos.sh](../scripts/build/macos.sh)
- [platforms/macos/README.md](../platforms/macos/README.md)
- [Casks/dau.rb](../Casks/dau.rb)
