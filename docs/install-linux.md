# Cài đặt Dấu trên Linux

Hướng dẫn cài **Dấu** 0.1.2 (Fcitx5) từ mã nguồn.

## Yêu cầu

- **Hệ điều hành:** Linux (x86_64 hoặc aarch64)
- **Fcitx5** đang dùng làm input method framework
- **Công cụ build:**
  - Rust toolchain (`cargo`, `rustc`) — [rustup.rs](https://rustup.rs)
  - CMake ≥ 3.16
  - Trình biên dịch C++17 (`g++` hoặc `clang++`)
  - Gói phát triển Fcitx5 (tên gói tùy distro), ví dụ Debian/Ubuntu:

```bash
sudo apt install fcitx5 fcitx5-config-qt \
  libfcitx5core-dev libfcitx5utils-dev libfcitx5config-dev \
  cmake g++ pkg-config
```

Kiểm tra Fcitx5:

```bash
fcitx5-remote -c   # hoặc: echo $GTK_IM_MODULE  # kỳ vọng fcitx
```

## Cài từ source (khuyến nghị)

Từ thư mục clone repo:

```bash
git clone https://github.com/hapo-nghialuu/dau.git
cd dau
./scripts/build.sh
./scripts/install.sh
```

Ba bước trên (clone + build + install) là luồng chuẩn ≤ 3 lệnh sau khi đã có dependency.

### User-local (mặc định, không sudo)

`./scripts/install.sh` cài vào `$HOME/.local`:

| Thành phần | Đường dẫn điển hình |
|------------|---------------------|
| Addon `.so` | `~/.local/lib/fcitx5/libdau.so` (hoặc multiarch) |
| Addon conf | `~/.local/share/fcitx5/addon/dau.conf` |
| Input method | `~/.local/share/fcitx5/inputmethod/dau.conf` |
| Icon | `~/.local/share/icons/hicolor/*/apps/dau.png` |

### System-wide

```bash
./scripts/build.sh
./scripts/install.sh --system
```

Prefix `/usr`, cần `sudo` khi install.

### Build debug

```bash
./scripts/build.sh --debug
```

### Dry-run (xem lệnh, không thực thi)

Hữu ích khi kiểm tra script trên máy không có Fcitx5 (ví dụ macOS):

```bash
./scripts/build.sh --dry-run
./scripts/install.sh --dry-run
./scripts/uninstall.sh --dry-run
```

## Kích hoạt trong Fcitx5

1. Mở **fcitx5-configtool** (hoặc *Fcitx 5 Configuration*).
2. Tab **Input Method** → **+** (Add) → bỏ tick “Only Show Current Language” nếu cần.
3. Tìm **Dấu** → Add.
4. Đặt Dấu trong danh sách input method (ví dụ cạnh bàn phím tiếng Anh).
5. Khởi động lại Fcitx5:

```bash
fcitx5 -r
```

6. Chuyển sang Dấu bằng phím nóng Fcitx5 (mặc định thường là `Ctrl+Space` hoặc `Super+Space` — tùy cấu hình).

Thử gõ Telex: `vieejt` → *việt*.

## Gỡ cài

```bash
# User-local
./scripts/uninstall.sh

# System-wide
./scripts/uninstall.sh --system
```

Sau đó `fcitx5 -r`. Có thể gỡ “Dấu” khỏi danh sách input method trong configtool.

## Makefile

```bash
make build-addon   # gọi ./scripts/build.sh
make install       # gọi ./scripts/install.sh
make uninstall     # gọi ./scripts/uninstall.sh
```

## Troubleshoot

### Không thấy “Dấu” trong configtool

- Chạy lại `./scripts/install.sh` và kiểm tra file conf:

```bash
ls -la ~/.local/share/fcitx5/addon/dau.conf
ls -la ~/.local/share/fcitx5/inputmethod/dau.conf
ls -la ~/.local/lib/fcitx5/libdau.so \
      ~/.local/lib/*/fcitx5/libdau.so 2>/dev/null
```

- Khởi động lại Fcitx5 (`fcitx5 -r`) hoặc đăng xuất phiên desktop.
- Đảm bảo session đang dùng Fcitx5, không phải IBus/SCIM.

### Addon không load / crash khi chọn Dấu

- Xem log:

```bash
fcitx5 -r --verbose=5 2>&1 | tee /tmp/fcitx5.log
```

- Xác nhận core đã build: `ls core/target/release/libdau_core.a`
- Build lại sạch:

```bash
rm -rf platforms/linux/build
./scripts/build.sh && ./scripts/install.sh
```

### Gõ chồng chữ trong terminal (`ttitietie…` / `tieengs` → rác)

**Triệu chứng:** mỗi phím chèn thêm cả từ đang soạn (t + ti + tie + …). Trình duyệt / ô text GUI vẫn đúng.

**Nguyên nhân (đã xác nhận Ubuntu 24.04 GNOME Wayland):** app tới Fcitx5 qua **ibusfrontend** → `InputContext.program()` = `frontend:ibus` (không phải `gnome-terminal-server`). Resolver rơi **CommitAtom**; `deleteSurroundingText` hỏng trên VTE → chồng chữ.

**Cách xử lý (user, không cần rebuild):**

```bash
mkdir -p ~/.config/dau
# tối thiểu — key quan trọng:
cat >> ~/.config/dau/config.toml << 'EOF'
[apps]
"frontend:ibus" = "preedit"
"frontend:dbus" = "preedit"
"frontend:xim" = "preedit"
EOF
fcitx5 -r
```

Đóng hết terminal cũ, mở cửa sổ mới, gõ lại `tieengs`.

**Shipped profile:** gói cài đặt có `${prefix}/share/dau/profiles.toml` (cùng nội dung `frontend:*` + terminal). User file `~/.config/dau/config.toml` **đè** shipped khi trùng key.

**Xem app-id runtime:**

```bash
gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
  --method org.fcitx.Fcitx.Controller1.DebugInfo
# hoặc log category dau:
fcitx5 -rd --verbose=dau=5 2>&1 | grep strategy
```

### Session Ubuntu GNOME vẫn IBus (`XMODIFIERS=@im=ibus`)

`im-config -n fcitx5` + `~/.xinputrc` **không đủ** trên GNOME Wayland. Cần:

1. `~/.config/environment.d/99-fcitx5.conf` (`GTK_IM_MODULE` / `QT_IM_MODULE` / `XMODIFIERS=@im=fcitx`)
2. Autostart `fcitx5 -d`
3. **Logout / login** (bắt buộc)
4. Nếu IBus GNOME service vẫn chiếm: `systemctl --user mask org.freedesktop.IBus.session.GNOME.service` (hoàn nguyên bằng `unmask`)

Kiểm tra sau login:

```bash
echo "$XMODIFIERS $GTK_IM_MODULE $QT_IM_MODULE"   # kỳ vọng @im=fcitx / fcitx
pgrep -a fcitx5
```

### Gõ không dấu / preedit lạ trong terminal (khác chồng chữ)

- Một số terminal cần bật support input method (xem doc terminal).
- Thử app GUI (LibreOffice, trình duyệt) để phân biệt lỗi app vs addon.
- Xem chiến lược preedit/backspace trong [design-per-app-typing.md](design-per-app-typing.md).

### Build lỗi “Fcitx5Core not found”

Cài gói `*-dev` Fcitx5 và `pkg-config`. Trên macOS addon **không** được hỗ trợ v1 — chỉ build core được (`./scripts/build.sh` sẽ cảnh báo).

### Kiểm tra metadata repo

```bash
./scripts/check-metadata.sh
```

## Liên kết

- [README](../README.md)
- [Hướng dẫn phát triển](development.md)
- Repo: https://github.com/hapo-nghialuu/dau
