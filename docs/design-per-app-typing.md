# Dấu — Thiết kế: Chiến lược gõ per-app & tự thích nghi (v1 Linux)

> **Trạng thái:** ĐÃ DUYỆT (2026-07-22, brainstorm với user) · Neo gốc: `project-anchor.md`
> Phạm vi: v1 Linux (Fcitx5-only). Đo đạc timing runtime = macOS phase 2, KHÔNG làm ở v1.

## 1. Vấn đề

Bộ gõ kiểu cũ (UniKey/gonhanh-macOS) sửa chữ bằng cách gửi **backspace giả + chuỗi mới**. Trong terminal/AI CLI (Claude Code vẽ lại dòng input liên tục), backspace rơi sai thời điểm → **nuốt/dính chữ**. gonhanh chữa bằng delay chỉnh tay per-app — trải nghiệm tệ, mỗi máy phải tự dò.

**Giải pháp của Dấu:** giải bằng **kiến trúc** (IM protocol chuẩn), không phải dò delay:
- **Preedit**: chuỗi đang gõ dở do app tự vẽ (gạch chân) — chưa có ký tự thật trong document.
- **Commit**: hoàn tất từ → gửi **nguyên từ trong 1 message**. Không backspace → không race → không thể nuốt chữ.

## 2. Chiến lược gõ (typing strategies)

| Strategy | Hành vi | Dùng khi |
|---|---|---|
| `preedit` *(mặc định)* | Soạn dở hiện gạch chân, commit nguyên từ khi kết thúc | Terminal, AI CLI, app lạ — an toàn tuyệt đối |
| `commit-atom` | Không preedit; commit từng cụm hoàn chỉnh ngay khi xác định | App preedit lỗi, hoặc app văn bản muốn cảm giác UniKey |
| `passthrough` | Tắt Dấu cho app này | User chọn |

**Preedit-first** (user đã duyệt): terminal/app lạ dùng `preedit`; app văn bản hỗ trợ tốt dùng `commit-atom` để chữ nhảy liền như UniKey.

## 3. Strategy Resolver — 3 lớp (đã duyệt: phương án A)

```
App focus thay đổi (Fcitx5 báo app-id + capability flags)
        │
        ▼
┌─ Strategy Resolver (bridge C++) ───────────────────┐
│ Ưu tiên: 1. User override  (~/.config/dau/apps.toml)│
│          2. Shipped profiles (đóng gói theo app)    │
│          3. Suy từ capability flags                 │
└────────────────────┬────────────────────────────────┘
                     ▼
        Strategy cho InputContext hiện tại
```

- **Lớp 1 — Capability detection (runtime):** đọc cờ `Preedit`, `SurroundingText`… của app khi focus. App không khai `Preedit` → `commit-atom`.
- **Lớp 2 — Shipped profiles:** cờ có thể "nói dối" (khai preedit nhưng render lỗi) → ship bảng TOML hành vi **đã test thật** cho từng app. Đây là "kiến thức" thay việc user tự dò.
- **Lớp 3 — User override:** cùng schema, đè lên shipped profiles. Van xả khi gặp app lạ.

Deterministic: cùng app → cùng hành vi. Không đo đạc, không ML, không chờ "học".

**Nguyên tắc phân lớp:** Core Rust **không biết app** — nhận phím, trả trạng thái từ đang soạn + từ hoàn chỉnh. "Thể hiện ra sao" (preedit/commit) là việc của bridge. Core sạch → unit-test 100%.

### Schema `apps.toml`

```toml
# Shipped: /usr/share/dau/profiles.toml · User: ~/.config/dau/apps.toml (đè)
[app."org.wezfurlong.wezterm"]
strategy = "preedit"          # preedit | commit-atom | passthrough

[app."Alacritty"]
strategy = "commit-atom"      # ví dụ: preedit render lỗi ở bản cũ
notes = "alacritty <0.13 preedit không vẽ gạch chân"
```

## 4. Ma trận app v1 (đã duyệt: Rộng + Warp, chia tier)

| Tier | Cam kết | Danh sách |
|---|---|---|
| **T1 — First-class** (chặn release) | Gõ đúng 100%, không nuốt/dính chữ, checklist test thủ công | GNOME Terminal, Konsole, Kitty, Ghostty, Alacritty × Claude Code, Codex CLI; tmux trong các terminal đó |
| **T2 — Best-effort** (không chặn release) | Hoạt động được; quirk ghi vào profile | **Warp**, VS Code integrated terminal, JetBrains terminal, aider, gemini-cli |
| **Smoke** | Gõ được câu tiếng Việt cơ bản | Firefox, Chrome, LibreOffice Writer/Calc |

Warp ở T2 vì IME support lịch sử không ổn định, bản Linux mới — **verify trong spike**; tốt thì thăng T1.

## 5. Fallback & recovery

- ESC/phím break → core clear buffer, preedit hủy sạch, không để rác.
- App lạ ngoài profile → mặc định `preedit`; không khai `Preedit` capability → `commit-atom`.
- App lỗi → user sửa bằng 1 dòng `apps.toml` (v1) — không chờ release mới.
- Không telemetry → quirk thu qua **cộng đồng đóng góp profiles** trên GitHub.

## 5b. Feature toggles theo strategy (phát hiện khi làm P1.5–1.6, 2026-07-22)

Engine core hỗ trợ `set_auto_capitalize(bool)` và `set_auto_restore(bool)`. Bridge PHẢI bật/tắt đúng theo ngữ cảnh app, nếu không sẽ phá north star:

| Feature | Terminal / AI CLI | App văn bản (docx/browser) | Lý do |
|---|---|---|---|
| **auto-capitalize** | **TẮT** | BẬT | Nếu bật, `git`→`Git`, `ls`→`Ls` trong terminal → hỏng lệnh. Đây là bug tiềm ẩn nếu để mặc định. |
| **auto-restore tiếng Anh** | BẬT | BẬT | Có lợi cả hai: gõ lệnh/English trong terminal tự khôi phục. |

→ Strategy Resolver (§3) khi áp strategy cho InputContext cũng set 2 cờ này: `preedit`/`commit-atom` trong nhóm terminal → `auto_capitalize=false`. Ghi vào `apps.toml` được (override per-app). **Task Phase 2 (P2.3/P2.4) phải thực hiện điều này.**

## 6. Ranh giới v1 (KHÔNG làm)

- Không đo timing runtime (macOS phase 2). Không ML. Không X11 fake-key path trừ khi spike chứng minh bắt buộc. Không IBus (fast-follow sau v1).

## 7. Định nghĩa "hoàn chỉnh" cho v1 (user bổ sung 2026-07-22)

v1 = **sản phẩm hoàn chỉnh**, không phải addon thô:
- **Icon/logo** riêng (hicolor theme, đủ size), hiển thị đúng trong fcitx5 UI/tray.
- **UI đồng nhất**: mọi surface cấu hình theo một hệ thống style, đặt tên, thuật ngữ thống nhất (Telex/VNI, chiến lược gõ...).
- **Thông tin chính xác**: tên "Dấu", version semver, mô tả, license, website/repo — nhất quán ở mọi nơi (`.conf`, package metadata, About, README).

## 8. Decision Register

| ID | Quyết định | Lựa chọn | Ngày |
|---|---|---|---|
| D-001 | Chế độ gõ mặc định Linux | **Preedit-first** (terminal preedit, app văn bản commit-atom) | 2026-07-22 |
| D-002 | Mức tự thích nghi v1 | **A — Capability + shipped profiles + user override**; đo đạc runtime → macOS phase 2 | 2026-07-22 |
| D-003 | Ma trận app v1 | **Rộng + Warp**, chia T1/T2/Smoke; Warp ở T2 chờ spike | 2026-07-22 |
| D-004 | Định nghĩa done v1 | **Product-grade**: icon, UI đồng nhất, thông tin chính xác | 2026-07-22 |
| D-005 | Quy trình thực thi | **Không dùng /specs**; plan chi tiết trong `plans/`, delegate cho grok | 2026-07-22 |

Quyết định nền (phiên trước, xem `project-anchor.md`): Rust core tự viết + FFI, Fcitx5-only, Linux-first, config TOML.
