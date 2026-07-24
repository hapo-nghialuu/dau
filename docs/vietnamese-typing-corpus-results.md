# Kết quả kiểm thử gõ tiếng Việt — `dau-core`

> **Ngày:** 2026-07-24  
> **Nhánh:** `feature/macos-start`  
> **Phạm vi:** engine Rust (`dau-core`) — Telex + VNI (CORPUS-04 strict, paired).  
> **Package:** `plans/macos-smoke-gaps.md` → CORPUS-04  
> **Cách chạy lại:**
>
> ```bash
> cargo test --manifest-path core/Cargo.toml --test full_vietnamese_corpus -- --nocapture
> # report cùng dataset/run: core/target/corpus-report.md
> ```

## Receipt run (2026-07-24)

| Field | Value |
|-------|--------|
| Command | `cargo test --manifest-path core/Cargo.toml --test full_vietnamese_corpus -- --nocapture` |
| Exit | **0** |
| Paired unique words | **141** (mỗi word: Telex + VNI) |
| Telex paired | **141 PASS / 0 FAIL** |
| VNI paired | **141 PASS / 0 FAIL** |
| Solo shape/undo | **31 PASS / 0 FAIL** |
| ALL FAIL | **0** |
| Soft gate `PASS >= 100` | **đã gỡ** — mọi mismatch panic/`assert!` |
| Report artifact | `core/target/corpus-report.md` (sinh cùng run) |

## Tóm tắt CORPUS-04

| Bộ | PASS | FAIL | Ghi chú |
|----|------|------|---------|
| Paired common words (unique) | **141** | **0** | mỗi expected có Telex **và** VNI |
| Telex paired | **141** | **0** | strict |
| VNI paired | **141** | **0** | strict |
| Solo shape/undo | **31** | **0** | base tones + undo double-key / `z` |

**Gate:**

1. `unique expected words >= 100`
2. Không duplicate expected trong paired inventory
3. `failures.is_empty()` — **0** mismatch được phép

### Ý nghĩa

- **Gõ được:** `Engine::process_char` từng phím → `composing()` **trùng** từ kỳ vọng.
- Sequence **chuẩn hoá theo engine** (không nới engine để pass input sai).
- **Không claim** cover 100% từ điển tiếng Việt.

### Sáu sequence dữ liệu cũ (đã sửa)

| Cũ (sai) | Kỳ vọng | Sequence chuẩn (CORPUS-04) |
|----------|---------|----------------------------|
| Telex `viecj` | việc | `vieecj` |
| Telex `thaangs` | tháng | `thangs` |
| Telex `moowis` | mới | `mowis` |
| Telex `cuwx` | cũ | `cux` |
| Telex `ddocs` | đọc | `ddojc` |
| VNI `cu74` | cũ | `cu4` |

Các sequence chuẩn khác cùng nhóm:

| Kỳ vọng | Telex | VNI |
|---------|-------|-----|
| tiếng | `tieengs` | `tie6ng1` |
| Việt / việt | `Vieejt` / `vieejt` | `Vie6t5` / `vie6t5` |
| người | `nguoiwf` | `nguoi72` |
| được | `dduwowcj` | `d9u7o7c5` |
| đọc | `ddojc` | `d9oc5` |
| Dấu | `Daasu` | `Da6u1` |

### Engine gap đã biết (không trong paired strict)

| Gõ chuẩn (UniKey-style) | Kỳ vọng | Thực tế engine | Ghi chú |
|-------------------------|----------|----------------|---------|
| Telex `gif` / VNI `gi2` | gì | `gif` / `gi2` (không đổi) | `gi` + thanh chưa map; **không** đổi engine trong CORPUS-04. Paired corpus dùng *nào* (`nafo` / `na2o`). |

## Nhóm coverage (paired)

| Nhóm | Ví dụ expected |
|------|----------------|
| function | và, của, là, có, không, một, những, được, trong, với, … |
| chat | xin, chào, bạn, cảm, ơn, tôi, chúng, ta, … |
| shape | năm, cần, biết, Việt, mới, nước, cũ, đọc, … |
| hard | người, trường, bước, tiếng, thuế, khoẻ, thuỷ, … |
| upper | Hoà, Việt, Đà, Nẵng, Dấu |
| extra | đi, nhà, máy, phím, chữ, sáng, tối, … (≥100 unique paired) |

## Source of truth

| File | Vai trò |
|------|---------|
| `core/tests/full_vietnamese_corpus.rs` | Dataset paired + solo; gate strict |
| `core/target/corpus-report.md` | Bảng PASS/FAIL sinh **cùng run** test |
| `docs/vietnamese-typing-corpus-results.md` | Receipt + tóm tắt (file này) |

Chi tiết từng case: mở `core/target/corpus-report.md` sau khi chạy test (cột Telex KQ / VNI KQ toàn **PASS** ở receipt trên).
