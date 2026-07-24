# Dấu — Tài liệu neo (Source of Truth)

> **Trạng thái:** Đang triển khai · **Ngày tạo:** 2026-07-21 · **Cập nhật:** 2026-07-24.
> **Code:** Linux Fcitx5 bridge + `dau-core` **v0.1** đã có; macOS bridge (CGEventTap + Swift menu bar) **đang làm** trên `platforms/macos/`. Không còn giai đoạn “chưa viết code”.
> Đây là tài liệu **neo** — nguồn chân lý cho tầm nhìn, phạm vi, và quyết định kiến trúc cấp cao của dự án Dấu. Mọi spec/task/PR về sau phải nhất quán với tài liệu này. Khi một quyết định ở đây thay đổi, cập nhật tại đây trước.

---

## 1. Dấu là gì

**Dấu** là bộ gõ tiếng Việt (Vietnamese Input Method Engine) **miễn phí, mã nguồn mở, offline 100%** cho **Linux và macOS**.

Tên "Dấu" gợi tới **dấu thanh** tiếng Việt (sắc/huyền/hỏi/ngã/nặng) — thứ định danh của chữ Quốc ngữ. ASCII: `dau`.

Triết lý: **Cài là dùng.** Nhanh, ổn định, quen thuộc như UniKey ngày trước — nhưng hiện đại, đa nền tảng, và **đặc biệt mượt trong terminal & các AI CLI** (Claude Code, Codex...).

### Câu định vị một dòng
> Bộ gõ tiếng Việt duy nhất coi **terminal và AI CLI là công dân hạng nhất**, chạy chung một core Rust trên Linux và macOS.

---

## 2. North Star — 4 cam kết cốt lõi

Đây là kim chỉ nam. Mọi tính năng phải phục vụ ít nhất một trong bốn, và **không được vi phạm** bất kỳ cái nào.

### 2.1. Terminal & AI CLI là hạng nhất 🔥 *(điểm khác biệt chính)*
- Gõ tiếng Việt mượt trong **terminal** (GNOME Terminal, Konsole, Kitty, Alacritty, Ghostty, iTerm2, Terminal.app) và **AI CLI** (Claude Code, Codex, Gemini CLI, Aider...).
- **Không nuốt chữ, không dính chữ** khi tool phản hồi nhanh/render lại màn hình.
- Xử lý **timing/delay per-app, hướng tới tự thích nghi (auto-adaptive)** — gonhanh đã có per-app delay nhưng người dùng phải *chỉnh tay* cho từng app/từng máy; Dấu đặt mục tiêu tự dò và thích nghi, đặc biệt trên Linux nơi gonhanh mới ở beta.
- Lý do tồn tại: các bộ gõ hiện tại thường lỗi khi làm việc với Claude Code / IDE tích hợp AI.

### 2.2. Tương thích hệ thống văn bản
- Hoạt động đúng trong **docx (Word/LibreOffice Writer), Excel/Calc, Google Docs**, trình duyệt, editor, chat.
- Chọn **đúng phương thức gửi text** theo loại ô nhập: *Backspace method* (mặc định, ~90% app) vs *Selection method* (address bar, combobox, Excel, autocomplete) để tránh dính/mất chữ.
- Nhận diện ứng dụng qua Accessibility/IME context, không chỉ dựa tên process.

### 2.3. UX thân thiện kiểu UniKey
- **Telex + VNI**, gõ tắt (shortcut), tự đặt dấu chuẩn (`hoà`, `khoẻ`, `thuỷ`), tự viết hoa đầu câu.
- **Auto-restore tiếng Anh** (gõ `text`, `push`, `sort` → tự khôi phục khi Space) và **ESC để khôi phục** — không phải tắt bộ gõ khi lẫn tiếng Anh.
- **Chuyển chế độ thông minh:** nhớ ON/OFF theo từng app; tự tắt khi input source là tiếng Nhật/Hàn/Trung.
- Menu bar (macOS) / system tray (Linux) đơn giản, không rối.

### 2.4. Privacy tuyệt đối & offline
- **Không telemetry, không thu thập dữ liệu, không quảng cáo, không bản Pro.**
- **100% offline** — không cần Internet để chạy (chỉ dùng mạng khi người dùng chủ động kiểm tra cập nhật).
- Mã nguồn mở, minh bạch.

### 2.5. Bổ sung: Hiệu năng & nhẹ *(điều kiện nền)*
- Mục tiêu **<1ms latency mỗi phím**, **RAM thấp (~5–20MB)** — bám chuẩn gonhanh đã đạt.
- Một core, nhiều nền tảng: sửa logic một chỗ, cả Linux và macOS cùng hưởng.

---

## 3. Phạm vi (Scope)

### 3.1. Trong phạm vi (v1)
- Nền tảng: **Linux (ưu tiên trước)**, sau đó **macOS**.
- Kiểu gõ: **Telex, VNI**.
- Tính năng gõ: đặt dấu chuẩn, gõ tắt, auto-restore tiếng Anh, ESC-restore, tự viết hoa, smart mode per-app.
- Tương thích: terminal, AI CLI, docx, excel, trình duyệt, editor, chat.
- UI cấu hình: tray/menu bar + cửa sổ Settings (chọn kiểu gõ, gõ tắt, per-app delay/method).

### 3.2. Ngoài phạm vi (v1 — cân nhắc sau)
- **Windows** (gonhanh có, Dấu để giai đoạn sau).
- Cloud sync, gợi ý gõ tắt bằng ML, từ điển tra cứu, editor dấu nâng cao.
- Mobile (iOS/Android).

### 3.3. Không bao giờ làm
- Thu phí, quảng cáo, telemetry, gửi dữ liệu gõ ra ngoài.

---

## 4. Kiến trúc cấp cao (đã chốt hướng)

**Mô hình:** *shared core + platform bridge* — đã được gonhanh chứng minh khả thi.

```
        Phím người dùng gõ
               │
   ┌───────────┴───────────┐
   │                       │
 Linux                   macOS
 Fcitx5 addon            CGEventTap primary
 (C++ bridge)            (Swift menu-bar / accessory)
   │                       │
   └───────────┬───────────┘
               │  FFI (C ABI)
        ┌──────┴───────┐
        │  Core (Rust) │  ← thuần logic, zero platform-dep
        │  pipeline 7  │
        │  giai đoạn   │
        └──────────────┘
               │
   action + backspace count + output chars
               │
   Bridge gửi text lại đúng phương thức (Backspace / Selection)
```

### 4.1. Quyết định kiến trúc

| Hạng mục | Quyết định | Ghi chú |
|---|---|---|
| **Ngôn ngữ core** | **Rust** (zero production dep) | An toàn bộ nhớ, <1ms, bind cả 2 OS qua FFI C ABI |
| **FFI interface** | Hàm kiểu `ime_key(...) -> Result` | `Result` `#[repr(C)]`: `chars[u32;N]`, `action`, `backspace`, `count`. Bridge phải khớp byte-for-byte |
| **Linux bridge** | **Fcitx5-only** (C++ addon) — đã chốt | X11 + Wayland; IBus = fast-follow sau v1 |
| **macOS bridge** | **CGEventTap primary** + Swift menu bar / accessory app — đã chốt (2026-07-24) | **IMK không phải primary.** AX chỉ cho onboarding, app context và full-parity injection fallback |
| **Ưu tiên build** | **Linux trước → macOS sau** | Ngược với gonhanh (họ macOS trước) |
| **Gửi text** | 2 method: Backspace / Selection | Chọn theo app qua Accessibility/context |
| **Config** | File **TOML**, core Rust parse | Linux: `~/.config/dau/` (XDG); macOS: `~/Library/Application Support/dau/`. Một format, hai đường dẫn chuẩn OS — không phụ thuộc dconf |

**Ghi chú macOS bridge (đã chốt cùng §8.6):**

- **C ABI không đổi** ở MVP: dùng nguyên `DauAction` + UTF-32 `chars` từ `dau_core.h`. Swift map text hiện tại; **số backspace là provisional do bridge đếm** từ output đã inject — **không thêm `backspace` vào `DauResult` ở MVP**.
- Injection method / delay / AX role thuộc trách nhiệm bridge macOS; core vẫn không biết app hay terminal.
- Engine config vẫn TOML qua `dau_load_config`. Profile injection macOS-only (per-app method/delay) lưu bridge-owned state (`UserDefaults` / shipped `profiles.toml`) cho đến khi có quyết định FFI/config snapshot riêng.
- Chi tiết build/dev: `platforms/macos/README.md`, `scripts/build/macos.sh`.

### 4.2. Core pipeline (tham khảo gonhanh, sẽ tinh chỉnh)
7 giai đoạn *validation-first* (kiểm tra âm tiết hợp lệ **trước khi** biến đổi):
1. Stroke (đ/Đ) → 2. Tone marks (thanh) → 3. Vowel marks (dấu mũ/móc/trăng) → 4. Mark removal (revert) → 5. W-vowel (Telex `w`→`ư`) → 6. Normal letter → 7. Shortcut expansion.

5 quy tắc validation phonology: (1) phải có nguyên âm, (2) phụ âm đầu hợp lệ, (3) mọi ký tự parse được, (4) quy tắc chính tả (c/k/g), (5) phụ âm cuối hợp lệ.

> ✅ **Đã chốt (2026-07-21):** Dấu **tự viết core Rust từ đầu**, tham khảo thuật toán/kiến trúc gonhanh để học — **không copy code**. Lý do: sạch license, tự do thiết kế cho per-app timing, hiểu sâu từng dòng để debug về sau.
> ⚠️ **Chưa chốt:** buffer size, thứ tự chính xác stage tone/mark — quyết trong `/hapo:brainstorm` → `/hapo:specs`.

### 4.3. Rủi ro kỹ thuật đã biết

- **Hai OS = hai bài toán terminal khác nhau.** gonhanh chạy được mọi terminal trên macOS nhờ CGEventTap (hook phím *toàn cục*). Trên Linux, addon Fcitx5 phụ thuộc **từng app tự implement IM protocol**: VTE (GNOME Terminal) tốt, Kitty/Alacritty nhiều quirk lịch sử, và **Wayland cấm global hook**. "AI CLI first-class trên Linux" phải giải bằng per-app strategy (tham khảo ibus-bamboo: ~6 chế độ gõ chọn theo app).
- **Wayland input-method protocol** (text-input-v3) chưa chắc đủ khả năng cho mọi ngữ cảnh → cần **spike kỹ thuật sớm nhất**, trước khi cam kết thiết kế chi tiết.
- **Scope v1 hiện bằng feature set nhiều năm của gonhanh** → phải cắt MVP bên trong v1 (đề xuất: Telex + Fcitx5 + danh sách app đích được test) trước khi vào specs.

---

## 5. Quan hệ với Gõ Nhanh (gonhanh.org)

`~/Desktop/gonhanh.org` là **nguồn tham khảo kiến trúc chính** (BSD-3/GPL, mã nguồn mở, cùng mô hình Rust core + bridge).

- **Học được:** mô hình FFI, pipeline validation-first, cách chọn Backspace/Selection theo app, cấu trúc thư mục (`core/` + `platforms/` + `docs/`).
- **Khác biệt của Dấu:**
  - **Linux-first** (gonhanh macOS-first; bản Linux của họ mới beta, ~500 LOC).
  - **Terminal & AI CLI trọng tâm số 1, nói chính xác:** gonhanh trên macOS *đã* quảng bá fix Claude Code và có per-app delay nhưng phải **chỉnh tay** ("mỗi máy, mỗi IDE hãy tự chỉnh delay"). Dấu nhắm: (a) trải nghiệm tương đương trên **Linux** — nơi chưa ai làm tốt, (b) delay **tự thích nghi** thay vì bắt người dùng tự dò.
- **Ranh giới pháp lý:** docs gonhanh tự mâu thuẫn về license (README: BSD-3-Clause; PDR: GPL-3.0). Dấu **tự viết core, chỉ học ý tưởng** nên không vướng; nếu sau này muốn copy bất kỳ đoạn code nào, phải đọc file `LICENSE` của họ trước.

---

## 6. Người dùng mục tiêu

- **Chính:** Dev/kỹ sư Việt Nam dùng **terminal + AI CLI** hằng ngày trên Linux/macOS, cần gõ tiếng Việt lẫn tiếng Anh liên tục mà không lỗi.
- **Phụ:** Người dùng văn phòng (docx/excel), sinh viên, ai muốn một bộ gõ nhẹ - sạch - riêng tư.

---

## 7. Thuật ngữ

| Thuật ngữ | Nghĩa |
|---|---|
| **IME** | Input Method Engine — bộ gõ |
| **Telex / VNI** | Hai kiểu gõ tiếng Việt phổ biến |
| **FFI** | Foreign Function Interface — cầu nối Rust ↔ C++/Swift |
| **Backspace method** | Xóa N ký tự rồi gửi ký tự mới |
| **Selection method** | Bôi đen (Shift+Left) N ký tự rồi thay — cho address bar/combobox/Excel |
| **Auto-restore** | Tự khôi phục từ tiếng Anh bị nhận nhầm thành dấu |
| **Bridge** | Lớp nền tảng nối core với hệ điều hành |

---

## 8. Quyết định đã chốt & câu hỏi còn mở

### Đã chốt (2026-07-21)
1. ~~Fcitx5-only hay cả IBus?~~ → **Fcitx5-only cho v1** (chắc chắn); IBus là fast-follow sau v1.
2. ~~Tự viết core hay fork gonhanh?~~ → **Tự viết core Rust, tham khảo thuật toán** (xem 4.2).
3. ~~Nơi lưu config?~~ → **File TOML**, core Rust parse. Linux: `~/.config/dau/` (XDG); macOS: `~/Library/Application Support/dau/`. Không phụ thuộc dconf/registry — một format, dễ backup/sync tay.

### Còn mở (đã thống nhất cách giải)
4. Cơ chế **per-app delay / tự thích nghi cho AI CLI** → **đề tài brainstorm đầu tiên** (điểm khác biệt cốt lõi, cần R&D riêng).
5. Wayland input method protocol đủ khả năng như X11 không? → **spike kỹ thuật số 1** khi bắt đầu code.
6. ~~macOS bridge: CGEventTap hay IMK?~~ → **đã chốt CGEventTap primary** (xem §8.6, 2026-07-24).
7. Ma trận hỗ trợ IME của các terminal Linux (VTE/Konsole/Kitty/Alacritty/Ghostty) — khảo sát thực tế trong spike Wayland.

### 8.6. Quyết định macOS bridge (2026-07-24)

Decision register — **locked** (đồng bộ plan `plans/macos-eventtap-parity.md` §10):

1. **Q1** → **CGEventTap** là primary path; **IMK / Input Method Kit không phải primary**.
2. **Q2** → **Terminal và AI CLI là north star**; MVP macOS phải có terminal vertical slice (gõ Telex/VNI trong Terminal/iTerm/AI CLI).
3. **Q3** → Hai release path đều supported: **dev ad-hoc + Accessibility (TCC user grant)** và **public Developer ID + notarize** (P4).
4. **Q4** → **Full parity Gõ Nhanh theo phase**: menu bar, injection matrix, per-app enabled/method/delay, AX onboarding/context, input-source gating, watchdog/recovery — không one-shot.
5. Tham khảo `~/Desktop/gonhanh.org` **chỉ ở mức pattern / kiến trúc**; Dấu **tự viết**, **không copy/fork** code gonhanh.
6. **`DauResult` / C ABI không thêm field `backspace` ở MVP**; bridge tính provisional backspace count từ output đã inject. Chỉ mở rộng C ABI khi có failing evidence từ case đã cam kết (P0).

---

*Cập nhật tài liệu này khi bất kỳ quyết định cấp cao nào thay đổi. Các tài liệu chi tiết (system-architecture, core-engine-algorithm, roadmap) sẽ tạo sau khi chốt spec.*
