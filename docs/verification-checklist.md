# Dấu — Checklist kiểm thử runtime trên Linux (Phase 4)

> Mục đích: verify runtime THẬT mà CI không thay được (gõ trong terminal/AI CLI/app thật). Điền kết quả vào bảng, tune `config.toml` theo phát hiện.
> Trạng thái code: Phase 0-3 xong, CI xanh. Đây là P4.1/P4.2.

## 1. Chuẩn bị môi trường Linux

Chọn 1 trong:
- **Máy Linux thật** (khuyến nghị nhất — Wayland/X11 hành vi chuẩn).
- **VM**: UTM/Lima (macOS Apple Silicon) hoặc VirtualBox. Distro gợi ý: **Fedora KDE** (Fcitx5 sẵn, Wayland tốt) hoặc **Ubuntu 24.04 + KDE/GNOME**.
- Cần: desktop session (X11 hoặc Wayland), quyền cài gói.

## 2. Cài đặt

```bash
git clone https://github.com/hapo-nghialuu/dau.git && cd dau
# cài dep (xem docs/install-linux.md cho từng distro)
./scripts/build.sh && ./scripts/install.sh
fcitx5 -r    # restart fcitx5
```
Mở `fcitx5-configtool` → thêm **Dấu** vào danh sách input method → đặt phím chuyển (mặc định Ctrl+Space).

**Kiểm tra cơ bản trước khi vào ma trận:**
- [ ] Dấu xuất hiện trong fcitx5-configtool với **icon** đúng.
- [ ] Cấu hình (Kiểu gõ Telex/VNI, các toggle) hiện trong configtool.
- [ ] Gõ `tieengs` trong 1 ô text bất kỳ → ra `tiếng`.

## 3. Ma trận kiểm thử (điền kết quả)

Mỗi ô: gõ chuỗi test, quan sát. **PASS** = đúng chữ, không nuốt/dính chữ, preedit (gạch chân) hiển thị & commit đúng khi hết từ.

Chuỗi test chuẩn mỗi app:
1. `Vieejt Nam` → `Việt Nam`
2. `xin chaof cacs banj` → `xin chào các bạn`
3. Gõ tiếng Anh: `the quick brown fox ` → giữ nguyên (auto-restore)
4. `git status` (trong terminal) → KHÔNG thành `gít status` hay nuốt chữ
5. ESC giữa từ đang gõ → khôi phục raw

### Tier 1 — First-class (chặn release)

| App | Môi trường | Test 1-5 | Kết quả | Ghi chú |
|-----|-----------|----------|---------|---------|
| GNOME Terminal (VTE) | X11 / Wayland | | ⬜ | |
| Konsole | X11 / Wayland | | ⬜ | |
| Kitty | X11 / Wayland | | ⬜ | |
| Alacritty | X11 / Wayland | | ⬜ | |
| Ghostty | X11 / Wayland | | ⬜ | |
| **Claude Code** (trong terminal trên) | | | ⬜ | AI CLI — trọng tâm |
| **Codex CLI** | | | ⬜ | AI CLI — trọng tâm |
| tmux (trong terminal T1) | | | ⬜ | |

### Tier 2 — Best-effort (không chặn release)

| App | Kết quả | Ghi chú |
|-----|---------|---------|
| **Warp** | ⬜ | IME history không ổn — quyết T1/T2 sau test |
| VS Code integrated terminal | ⬜ | |
| JetBrains terminal | ⬜ | |
| aider / gemini-cli | ⬜ | |

### Smoke — app văn bản

| App | Test | Kết quả |
|-----|------|---------|
| Firefox (thanh địa chỉ + ô text) | `Vieejt` → `Việt` | ⬜ |
| Chrome | address bar (selection method) | ⬜ |
| LibreOffice Writer | đoạn văn có dấu | ⬜ |
| LibreOffice Calc | ô nhập | ⬜ |

## 4. Kiểm tra riêng north star (terminal/AI CLI)

- [ ] Gõ nhanh liên tục trong Claude Code khi nó đang render lại màn hình → **không nuốt chữ**.
- [ ] `git`, `ls`, `cd` → KHÔNG bị auto-hoa thành `Git`/`Ls` (auto-cap tắt cho terminal — design §5b).
- [ ] Preedit (gạch chân) hiển thị đúng trong terminal khi đang soạn từ.
- [ ] Chuyển app terminal→trình duyệt→terminal: strategy tự đổi đúng (không kẹt).

## 5. Tune theo kết quả

- App nào preedit lỗi/nuốt chữ → thêm vào `~/.config/dau/config.toml`:
  ```toml
  [apps]
  "app-id-thật" = "commit-atom"   # hoặc "passthrough"
  ```
  (lấy app-id qua `fcitx5` log category `dau`, hoặc `xprop`/`fcitx5-diagnose`).
- Cập nhật shipped `profiles.toml` (nếu có) với quirk phát hiện.
- **Quyết định Warp**: T1 nếu 5/5 test pass, giữ T2 nếu có lỗi.

## 6. Điều kiện DONE cho Phase 4 (P4.3 release v0.1.0)

- [ ] Toàn bộ Tier 1 PASS (không nuốt/dính chữ).
- [ ] North star §4 checklist PASS.
- [ ] profiles.toml/config cập nhật theo phát hiện.
- [ ] Tag `v0.1.0` + GitHub release + tarball; cài từ tarball trên VM sạch thành công.

## Ghi chú

- Bug gặp lúc test → tạo issue trên repo, hoặc báo lại để Claude sửa (qua grok) rồi push → CI → cài lại.
- Wayland vs X11 có thể khác nhau — test cả hai nếu được.
