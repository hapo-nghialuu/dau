# Kết quả kiểm thử gõ tiếng Việt — `dau-core` + regression gate (TG-06)

> **Ngày verify:** 2026-07-25  
> **Nhánh:** `feature/macos-start`  
> **HEAD code (product):** `7523970` (TG-05); TG-00 `d678cd4`; TG-01..04 `5eb43fc`  
> **Phạm vi file này:** biên nhận **deterministic** (Rust core + corpus).  
> **Không claim** live app smoke macOS (TextEdit/Terminal/browser/Electron / idle 30 phút) — xem `platforms/macos/README.md` §4b.

## Lệnh verify (chạy lại)

```bash
# Formatting (core only)
cargo fmt --manifest-path core/Cargo.toml --check
# Nếu fail: cargo fmt --manifest-path core/Cargo.toml  (chỉ formatting)

# Core unit + corpus
cargo test --manifest-path core/Cargo.toml
cargo test --manifest-path core/Cargo.toml --test full_vietnamese_corpus -- --nocapture
# report artifact: core/target/corpus-report.md

# macOS unit (không thay live smoke)
xcodebuild test \
  -project platforms/macos/Dau.xcodeproj \
  -scheme Dau \
  -destination 'platform=macOS'
```

## Receipt run (2026-07-25, worktree `feature-macos-start`)

| Kiểm tra | Kết quả (đo thực tế) |
|----------|----------------------|
| `cargo fmt --manifest-path core/Cargo.toml --check` | Lần đầu **FAIL** (thiếu `rustfmt` component + format drift). Đã `rustup component add rustfmt` + `cargo fmt` (chỉ `core/`: `vn_syllable.rs`, `full_vietnamese_corpus.rs`). Sau đó **PASS**. |
| `cargo test --manifest-path core/Cargo.toml` | **PASS**: **102** lib unit + **1** corpus integration; 0 fail; 0 doc-test |
| Corpus detail (nocapture) | **143** Telex paired PASS / 0 FAIL; **143** VNI paired PASS / 0 FAIL; **34** solo PASS / 0 FAIL; ALL FAIL **0** |
| `xcodebuild test … -scheme Dau -destination 'platform=macOS'` | **PASS**: **240** tests, 0 failure (`** TEST SUCCEEDED **`) |
| Live app matrix / idle-sleep soak | **Chưa chạy** — không PASS |

## Corpus paired / solo (CORPUS-04 strict)

| Bộ | PASS | FAIL | Ghi chú |
|----|------|------|---------|
| Paired unique words | **143** | **0** | mỗi expected: Telex **và** VNI |
| Telex paired | **143** | **0** | strict `composing() == expect` |
| VNI paired | **143** | **0** | strict |
| Solo shape/undo (+ `uaw`/`dduaw`) | **34** | **0** | base tones + undo + TG-01 `dduaw→đưa` |

**Gate:** `unique expected >= 100`, no duplicate expected, `failures.is_empty()`.

Artifact: `core/target/corpus-report.md` (sinh cùng run corpus).

### Ý nghĩa

- **Gõ được (core):** `Engine::process_char` từng phím → `composing()` trùng kỳ vọng.
- Sequence chuẩn hoá theo engine; **không** claim 100% từ điển tiếng Việt.
- Corpus **không** cover Backspace/edit/FFI/mac inject — các lớp đó ở unit riêng (bảng dưới).

### Sequence chuẩn (mẫu)

| Kỳ vọng | Telex | VNI |
|---------|-------|-----|
| tiếng | `tieengs` | `tie6ng1` |
| Việt / việt | `Vieejt` / `vieejt` | `Vie6t5` / `vie6t5` |
| người | `nguoiwf` | `nguoi72` |
| được | `dduwowcj` | `d9u7o7c5` |
| đưa | `dduaw` / `dduwa` | (solo Telex; paired qua corpus khác) |
| đâu / đầu | `ddaau` / `ddaauf` | `d9a6u` / `d9a6u2` |

### Engine gap đã biết (không trong paired strict)

| Gõ chuẩn (UniKey-style) | Kỳ vọng | Thực tế engine | Ghi chú |
|-------------------------|----------|----------------|---------|
| Telex `gif` / VNI `gi2` | gì | `gif` / `gi2` (không đổi) | `gi` + thanh chưa map. Paired dùng *nào* (`nafo` / `na2o`). |

## English restore + plain (unit, ngoài corpus file)

Nguồn: `core/src/engine/ux_tests.rs`, `evidence_tests.rs` (auto-restore on break).

| Nhóm | Cases (keys → commit/break) | File / test |
|------|----------------------------|-------------|
| English restore (Space) | `text`, `expect`, `with`, `wow`, `perfect`, `tesla`, `student`, `software`, `keyboard` → raw | `auto_restore_english_words` (**9** words) |
| English + punct break | `text.` `with,` `wow!` → raw | `auto_restore_also_on_punctuation` |
| Restore off | `text` + Space → `tẽt` (composed giữ) | `auto_restore_can_be_disabled` |
| Keep valid VN | `tieengs`→`tiếng`, `vieejt`→`việt`; multi-`w` `ươ*` | `auto_restore_keeps_*` |
| English progressive / delete | `delete` từng key + Space `delete ` | evidence + mac pipeline tests |
| Mix-box stay VN | `mix`→`mĩ`, `box`→`bõ` | `auto_restore_limits_mix_box_stay_vietnamese` |

## Edit / Backspace sequences (unit contract TG-03/TG-04)

Core (`backspace_one_display_scalar` / FFI `dau_backspace`) + mac pipeline/session:

| Sequence | Expected | Covered by |
|----------|----------|------------|
| `dduaw` / `dduwa` → BS → `a` | `đưa`→`đư`→`đưa` | `evidence_tests`, mac pipeline |
| `tieengs` → BS → `g` → Space | `tiếng`→`tiến`→`tiếng`→`tiếng ` | core + session |
| `tie6ng1` → BS → `g` | tương đương Telex | core + session |
| `delete` → BS → `e` → Space | `delete`→`delet`→`delete`→`delete ` | core + session |
| `aa` → BS | `â`→`""` (một scalar) | `backspace_aa_removes_one_display_unit` |
| BS lặp → rỗng → BS | mỗi event 1 scalar; rỗng = no-op / pass-through host | core + mac |
| Forward Delete (117) khi compose | pass-through + reset; **không** whole-wipe inject | mac classifier/pipeline/session |
| Cmd/Option+Delete | boundary; không inject whole-provisional wipe | mac tests |

**Grep gate (TG-06):** không còn XCTest assert whole-provisional wipe cho **physical Backspace** (key 51). Các assert hiện tại yêu cầu `backspace == 1` / “must **not** wipe entire provisional”. (Wipe provisional khi classifier `None` while composing vẫn là path riêng — không phải physical Backspace.)

## Nhóm coverage paired (tóm tắt)

| Nhóm | Ví dụ expected |
|------|----------------|
| function | và, của, là, có, không, một, những, được, … |
| chat | xin, chào, bạn, cảm, ơn, tôi, … |
| shape | năm, cần, biết, Việt, mới, nước, cũ, đọc, … |
| hard | người, trường, bước, tiếng, thuế, … |
| upper | Hoà, Việt, Đà, Nẵng, Dấu |
| extra | đi, nhà, đâu, đầu, kết, thúc, … |

## Source of truth

| File | Vai trò |
|------|---------|
| `core/tests/full_vietnamese_corpus.rs` | Dataset paired + solo; gate strict |
| `core/target/corpus-report.md` | Bảng PASS/FAIL sinh **cùng run** |
| `core/src/engine/evidence_tests.rs` / `ux_tests.rs` | Exact `dduaw`, English restore, Backspace edit |
| `platforms/macos/Tests/*` | Bridge/session/mapper; 240 XCTest |
| `docs/vietnamese-typing-corpus-results.md` | Receipt + tóm tắt (file này) |
| `plans/typing-gaps-dau-vs-gonhanh.md` | Status TG packages + S7 soak còn mở |

## Manual smoke còn mở (không ghi PASS)

1. TextEdit / Terminal / browser contenteditable / Electron: D1–D5, E1–E2, P1–P4  
2. Idle 30 phút + sleep/wake/lock ×5 (S7a/S7b) — EN và VI  
3. Nếu freeze: Sample Process **trước** quit (metadata only)
