# Corpus gõ tiếng Việt strict — `dau-core`

Ngày xác minh: 2026-07-24.

## Kết quả CI

Lần chạy mới nhất:

```bash
cd core
cargo test --test full_vietnamese_corpus
```

Kết quả: **2 test pass, 0 fail**.

| Fixture blessed | Dòng dữ liệu | Telex | VNI | Chính sách assert |
|---|---:|---:|---:|---|
| Từ có nghĩa, distinct | 120 | 120 | 120 | Mỗi từ phải đúng ở cả `composing()` và `on_break(' ').text` |
| Cụm từ ngắn | 15 | 15 | 15 | Mỗi thành phần phải đúng ở cả compose/commit; toàn cụm phải khớp |

Tổng cộng corpus chứa **120 từ distinct** và **15 cụm từ**. Mỗi dòng có
expected output tĩnh cùng một chuỗi canonical Telex và VNI; test không suy ra
expected output từ engine, không nuốt failure, không dùng pass threshold và
không ghi report phát sinh lúc chạy.

## Phạm vi ngôn ngữ

120 từ được chia thành 17 nhóm:

| Nhóm | Số từ | Nhóm | Số từ |
|---|---:|---|---:|
| action | 3 | common | 15 |
| communication | 6 | education | 12 |
| emotion | 3 | food | 13 |
| greeting | 4 | health | 1 |
| home | 6 | movement | 5 |
| people | 10 | place | 3 |
| position | 6 | quality | 11 |
| technology | 6 | time | 13 |
| work | 3 |  |  |

15 cụm từ phủ country, education, family, greeting, health, language, place,
technology, time và work. Ví dụ: `Việt Nam`, `Hà Nội`, `học sinh`, `công việc`,
`cảm ơn`, `buổi sáng`, `thành phố`, `gia đình`, `điện thoại`, `máy tính`.

Nguồn dữ liệu:

- `core/tests/data/blessed-vietnamese-words.tsv`
- `core/tests/data/blessed-vietnamese-phrases.tsv`

## Chính sách PASS

Một case chỉ PASS khi chuỗi canonical tĩnh cho đúng expected output ở phương
thức tương ứng. Bất kỳ mismatch nào đều làm test fail ngay; không có danh sách
known-fail trong blessed corpus.

Mỗi dòng dùng một chuỗi Telex/VNI quen thuộc, với tone/shape key ở vị trí gõ
phổ biến mà engine hỗ trợ. Token trong phrase tái sử dụng đúng mapping blessed
word nếu từ đó có trong word fixture. **Ngoại lệ nonstandard: 0**.

Các probe sequence thay thế, inventory mở rộng hoặc known gap mang tính khám
phá không thuộc CI corpus này và **không được tính là PASS**. Chúng chỉ là dữ
liệu điều tra cho thay đổi engine sau này.

## Auto-restore tiếng Anh khi bật Telex

Test hồi quy riêng kiểm tra:

- `tesst` đang compose thành `test` và commit `test` trên cả 8 break được hỗ
  trợ: Space, `.`, `,`, `!`, `?`, Enter, `;`, `:`.
- Khi tắt auto-restore, `tesst` vẫn commit display `test` như trước.
- `Tesst` giữ đúng chữ hoa; ESC trả chính xác raw `tesst`; `clear()` không làm
  rò trạng thái sang từ sau.
- 23 từ tiếng Anh phổ thông có phím dễ xung đột Telex vẫn commit raw, gồm
  `coffee`, `effect`, `class`, `address`, `different`, `success`, `book`,
  `feel` và các biến thể double-letter khác.
- Telex tiếng Việt (`tieengs` → `tiếng`) và hành vi VNI cũ vẫn giữ nguyên.

Raw key không đủ để phân biệt mọi ý định double-letter tiếng Anh. Vì vậy engine
chỉ bless chính xác mẫu được yêu cầu `tesst` → `test`; không dùng heuristic
rộng có thể làm hỏng `coffee`, `errs` hoặc `cliffs`. Khi có English lexicon thật,
danh sách này có thể mở rộng bằng fixture tĩnh và test hồi quy tương ứng.

## Xác minh cuối

`cargo check`, `cargo build`, `cargo test --all-targets` và `git diff --check`
đều pass: **88 unit + 2 corpus, 0 fail**. Review độc lập đạt **9.7/10, 0
Critical**. `rustfmt` và `clippy` chưa có trong toolchain local nên hai gate này
được ghi nhận là tooling gap, không báo pass giả.
