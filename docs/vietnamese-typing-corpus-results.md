# Kết quả kiểm thử gõ tiếng Việt — `dau-core` + regression repeat-escape

> **Ngày verify:** 2026-08-02
> **Nhánh:** `feature/macos-start`  
> **Phạm vi file này:** biên nhận **deterministic** (Rust core + corpus).  
> **Không claim** live app smoke macOS (TextEdit/Terminal/browser/Electron / idle 30 phút) — xem `platforms/macos/README.md` §4b.

## Lệnh verify (chạy lại)

```bash
cd core
cargo fmt --all -- --check
cargo test --lib
cargo test --test round_trip_vietnamese_corpus
cargo test --test daily_sentence_corpus
```

MacOS unit tests remain separate from core receipt:

```bash
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

## Receipt run (2026-08-02, repeat-escape)

| Kiểm tra | Kết quả (đo thực tế, run này) |
|----------|-------------------------------|
| `cargo fmt --manifest-path core/Cargo.toml --all -- --check` | **PASS** |
| `cargo test --manifest-path core/Cargo.toml` | **PASS**: **124** lib unit + daily/full/paired/round-trip integration + doc-tests; 0 fail |
| `cargo test --test round_trip_vietnamese_corpus` | **PASS**: **1** test; 0 fail; Telex/VNI **2000 PASS / 0 SKIP-KNOWN / 0 FAIL** |
| `cargo test --test daily_sentence_corpus` | **PASS**: **1050** alphabetic tokens across **130 unique** daily-use EN+VI sentences; Telex + VNI active |
| Telex collision behavior | Vietnamese wins: `mix`→`mĩ`, `box`→`bõ`, `six`→`sĩ`, `this`→`thí`, `been`→`bên`, `as`→`á`, `is`→`í`, `us`→`ú`, `or`→`ỏ` |
| Explicit raw-English escape | Repeat/manual escape required: `wwork`→`work`, `beeen`→`been`, `thiss`→`this`, `ass`→`as`, `tesst`→`test`, `aaa`→`aa`, `ddd`→`dd` |
| Corpus skip policy | Không còn accepted known gap trong top-2000 |

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

### Engine gap đã đóng

| Gõ chuẩn (UniKey-style) | Kỳ vọng | Thực tế engine | Ghi chú |
|-------------------------|----------|----------------|---------|
| Telex `gif` / VNI `gi2` | gì | `gì` / `gì` | Unit `gi_bare_tones` pass; ghi chú gap cũ đã stale. |

## Telex auto-restore + repeat-escape (unit, ngoài corpus file)

Nguồn: `core/src/engine/ux_tests.rs`, `core/src/engine/manual-revert-tests.rs`, `evidence_tests.rs`.

| Nhóm | Cases (keys → commit/break) | File / test |
|------|-----------------------------|-------------|
| Phonotactic + high-confidence raw restore | `text`, `expect`, `with`, `wow`, `perfect`, `tesla`, `case`, `luxury`, `things`, `kings`, `of`, `if`, `see`, `student`, `software`, `keyboard` → raw | `auto_restore_english_words` |
| Restore trên punctuation | `text.` `with,` `wow!` → raw | `auto_restore_also_on_punctuation` |
| Restore off | `text` + Space → `tẽt` (composed giữ) | `auto_restore_can_be_disabled` |
| Vietnamese hợp lệ | `tieengs`→`tiếng`, `vieejt`→`việt`; multi-`w` `ươ*` | `auto_restore_keeps_*` |
| Repeat/manual escape | `wwork`→`work`, `beeen`→`been`, `ass`→`as`, `tesst`→`test`, `aaa`→`aa`, `ddd`→`dd` | `repeat_escape_commits_composed_english`, `telex_w_repeat_escape_restores_literal_w_prefix` |
| Vietnamese wins | `mix`→`mĩ`, `box`→`bõ`, `six`→`sĩ`, `this`→`thí`, `been`→`bên`, `as`→`á`, `is`→`í`, `us`→`ú`, `or`→`ỏ` | `telex_vietnamese_wins_over_english_collisions` |
| English progressive / delete | `delete` từng key + Space `delete ` | evidence + mac pipeline tests |

## Top-2000 round-trip honest (2026-08-02)

Nguồn: `core/tests/round_trip_vietnamese_corpus.rs` (oracle độc lập qua bảng Unicode, không dùng engine internals).

| Method | Kết quả |
|--------|---------|
| Telex | **2000 PASS / 0 SKIP-KNOWN / 0 FAIL** |
| VNI | **2000 PASS / 0 SKIP-KNOWN / 0 FAIL** |

- Corpus không còn bỏ qua collision Telex.
- Continuous whole-text (2000 từ + Space): **PASS** cả Telex và VNI.
- `đắk`/`lắk` đã gõ được bằng exception final-`k` hẹp cho nucleus `ă`; `KNOWN_GAPS` hiện rỗng.

## Daily EN+VI sentence fixture (2026-08-02)

Nguồn: `core/tests/daily_sentence_corpus.rs` + `core/tests/data/daily-english-vietnamese-sentences.tsv`.

- **1050** alphabetic tokens từ **130 câu unique**, không dùng repeat multiplier.
- TSV 3 cột: `telex_keys`, `vni_keys`, `expected_text`; mỗi row là câu có whitespace + punctuation, không phải word-pair rời.
- Cover English khi Telex/VNI active: `case`, `luxury`, `things`, `kings`, `of`, `if`, `see`, `wwork`, `beeen`, `thiss`, `iss`, `tesst`, `keeep`, `carre`, `neww`, `lisst`, `currsor`, `barr`, `offf`, `docss`, `roww`/`rowws`, `dataa`, input/text area/terminal/code/email/browser/address bar/cursor.
- Cover Vietnamese everyday: chào bạn, hôm nay, công việc, buổi sáng, tiếng Việt, dữ liệu, máy tính, mạng, phím, nhà trường.

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
| `core/tests/round_trip_vietnamese_corpus.rs` | Top-2000 honest; Telex và VNI không còn accepted known gap |
| `core/target/corpus-report.md` | Bảng PASS/FAIL sinh **cùng run** |
| `core/src/engine/evidence_tests.rs` / `ux_tests.rs` / `manual-revert-tests.rs` | Exact `dduaw`, auto-restore, repeat-escape, Backspace edit |
| `platforms/macos/Tests/*` | Bridge/session/mapper; **293** XCTest (re-run 2026-08-01) |
| `docs/vietnamese-typing-corpus-results.md` | Receipt + tóm tắt (file này) |
| `plans/typing-gaps-dau-vs-gonhanh.md` | Status TG packages + S7 soak còn mở |

## Manual smoke còn mở (không ghi PASS)

1. TextEdit / Terminal / browser contenteditable / Electron: D1–D5, E1–E2, P1–P4  
2. Idle 30 phút + sleep/wake/lock ×5 (S7a/S7b) — EN và VI  
3. Nếu freeze: Sample Process **trước** quit (metadata only)
