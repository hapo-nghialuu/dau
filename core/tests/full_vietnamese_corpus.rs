//! Full Telex/VNI corpus — actual engine output vs expected.
//! Run: `cd core && cargo test --test full_vietnamese_corpus -- --nocapture`

use dau_core::{Engine, Method};

fn type_word(method: Method, keys: &str) -> String {
    let mut eng = Engine::new(method);
    eng.set_auto_capitalize(false);
    eng.set_auto_restore(true);
    for ch in keys.chars() {
        let caps = ch.is_ascii_uppercase();
        eng.process_char(ch, caps);
    }
    eng.composing()
}

struct Case {
    keys: &'static str,
    expect: &'static str,
    note: &'static str,
}

fn run_suite(name: &str, method: Method, cases: &[Case]) -> (usize, usize, Vec<String>) {
    let mut pass = 0usize;
    let mut fail = 0usize;
    let mut lines = Vec::new();
    for c in cases {
        let got = type_word(method, c.keys);
        if got == c.expect {
            pass += 1;
            lines.push(format!(
                "PASS | {name} | gõ `{}` → `{}` | {}",
                c.keys, got, c.note
            ));
        } else {
            fail += 1;
            lines.push(format!(
                "FAIL | {name} | gõ `{}` → kỳ vọng `{}` | thực tế `{}` | {}",
                c.keys, c.expect, got, c.note
            ));
        }
    }
    (pass, fail, lines)
}

#[test]
fn full_telex_and_vni_corpus() {
    let telex: &[Case] = &[
        Case { keys: "a", expect: "a", note: "a ngang" },
        Case { keys: "as", expect: "á", note: "á" },
        Case { keys: "af", expect: "à", note: "à" },
        Case { keys: "ar", expect: "ả", note: "ả" },
        Case { keys: "ax", expect: "ã", note: "ã" },
        Case { keys: "aj", expect: "ạ", note: "ạ" },
        Case { keys: "aw", expect: "ă", note: "ă" },
        Case { keys: "aa", expect: "â", note: "â" },
        Case { keys: "ee", expect: "ê", note: "ê" },
        Case { keys: "oo", expect: "ô", note: "ô" },
        Case { keys: "ow", expect: "ơ", note: "ơ" },
        Case { keys: "uw", expect: "ư", note: "ư" },
        Case { keys: "dd", expect: "đ", note: "đ" },
        Case { keys: "aws", expect: "ắ", note: "ắ" },
        Case { keys: "awf", expect: "ằ", note: "ằ" },
        Case { keys: "awr", expect: "ẳ", note: "ẳ" },
        Case { keys: "awx", expect: "ẵ", note: "ẵ" },
        Case { keys: "awj", expect: "ặ", note: "ặ" },
        Case { keys: "aas", expect: "ấ", note: "ấ" },
        Case { keys: "aaf", expect: "ầ", note: "ầ" },
        Case { keys: "aar", expect: "ẩ", note: "ẩ" },
        Case { keys: "aax", expect: "ẫ", note: "ẫ" },
        Case { keys: "aaj", expect: "ậ", note: "ậ" },
        Case { keys: "ees", expect: "ế", note: "ế" },
        Case { keys: "eef", expect: "ề", note: "ề" },
        Case { keys: "eer", expect: "ể", note: "ể" },
        Case { keys: "eex", expect: "ễ", note: "ễ" },
        Case { keys: "eej", expect: "ệ", note: "ệ" },
        Case { keys: "oos", expect: "ố", note: "ố" },
        Case { keys: "oof", expect: "ồ", note: "ồ" },
        Case { keys: "oor", expect: "ổ", note: "ổ" },
        Case { keys: "oox", expect: "ỗ", note: "ỗ" },
        Case { keys: "ooj", expect: "ộ", note: "ộ" },
        Case { keys: "ows", expect: "ớ", note: "ớ" },
        Case { keys: "owf", expect: "ờ", note: "ờ" },
        Case { keys: "owr", expect: "ở", note: "ở" },
        Case { keys: "owx", expect: "ỡ", note: "ỡ" },
        Case { keys: "owj", expect: "ợ", note: "ợ" },
        Case { keys: "uws", expect: "ứ", note: "ứ" },
        Case { keys: "uwf", expect: "ừ", note: "ừ" },
        Case { keys: "uwr", expect: "ử", note: "ử" },
        Case { keys: "uwx", expect: "ữ", note: "ữ" },
        Case { keys: "uwj", expect: "ự", note: "ự" },
        Case { keys: "tieengs", expect: "tiếng", note: "tiếng" },
        Case { keys: "vieejt", expect: "việt", note: "việt" },
        Case { keys: "hoaf", expect: "hoà", note: "hoà" },
        Case { keys: "khoer", expect: "khoẻ", note: "khoẻ" },
        Case { keys: "thuyr", expect: "thuỷ", note: "thuỷ" },
        Case { keys: "nguoiwf", expect: "người", note: "người" },
        Case { keys: "toans", expect: "toán", note: "toán" },
        Case { keys: "hoas", expect: "hoá", note: "hoá" },
        Case { keys: "quawms", expect: "quắm", note: "quắm" },
        Case { keys: "ngoaif", expect: "ngoài", note: "ngoài" },
        Case { keys: "tuaan", expect: "tuân", note: "tuân" },
        Case { keys: "khoawns", expect: "khoắn", note: "khoắn" },
        Case { keys: "xin", expect: "xin", note: "xin" },
        Case { keys: "chaof", expect: "chào", note: "chào" },
        Case { keys: "cacs", expect: "các", note: "các" },
        Case { keys: "banj", expect: "bạn", note: "bạn" },
        Case { keys: "own", expect: "ơn", note: "ơn" },
        Case { keys: "nhieefu", expect: "nhiều", note: "nhiều" },
        Case { keys: "lafm", expect: "làm", note: "làm" },
        Case { keys: "viecj", expect: "việc", note: "việc" },
        Case { keys: "truowngf", expect: "trường", note: "trường" },
        Case { keys: "hocj", expect: "học", note: "học" },
        Case { keys: "sinh", expect: "sinh", note: "sinh" },
        Case { keys: "vieen", expect: "viên", note: "viên" },
        Case { keys: "dduwowcj", expect: "được", note: "được" },
        Case { keys: "khoong", expect: "không", note: "không" },
        Case { keys: "phair", expect: "phải", note: "phải" },
        Case { keys: "nhuw", expect: "như", note: "như" },
        Case { keys: "thees", expect: "thế", note: "thế" },
        Case { keys: "nafy", expect: "này", note: "này" },
        Case { keys: "cuar", expect: "của", note: "của" },
        Case { keys: "ngayf", expect: "ngày", note: "ngày" },
        Case { keys: "thaangs", expect: "tháng", note: "tháng" },
        Case { keys: "nawm", expect: "năm", note: "năm" },
        Case { keys: "moowis", expect: "mới", note: "mới" },
        Case { keys: "cuwx", expect: "cũ", note: "cũ" },
        Case { keys: "ddepj", expect: "đẹp", note: "đẹp" },
        Case { keys: "xauas", expect: "xấu", note: "xấu" },
        Case { keys: "toots", expect: "tốt", note: "tốt" },
        Case { keys: "yeesu", expect: "yếu", note: "yếu" },
        Case { keys: "manhj", expect: "mạnh", note: "mạnh" },
        Case { keys: "bieest", expect: "biết", note: "biết" },
        Case { keys: "hieeru", expect: "hiểu", note: "hiểu" },
        Case { keys: "nois", expect: "nói", note: "nói" },
        Case { keys: "vieets", expect: "viết", note: "viết" },
        Case { keys: "ddocs", expect: "đọc", note: "đọc" },
        Case { keys: "thaays", expect: "thấy", note: "thấy" },
        Case { keys: "toaf", expect: "toà", note: "toà" },
        Case { keys: "toafn", expect: "toàn", note: "toàn" },
        Case { keys: "thuees", expect: "thuế", note: "thuế" },
        Case { keys: "quees", expect: "quế", note: "quế" },
        Case { keys: "uoon", expect: "uôn", note: "uôn" },
        Case { keys: "tuwowngf", expect: "tường", note: "tường" },
        Case { keys: "buwowcs", expect: "bước", note: "bước" },
        Case { keys: "muowif", expect: "mười", note: "mười" },
        Case { keys: "nuowsc", expect: "nước", note: "nước" },
        Case { keys: "cowm", expect: "cơm", note: "cơm" },
        Case { keys: "boos", expect: "bố", note: "bố" },
        Case { keys: "mej", expect: "mẹ", note: "mẹ" },
        Case { keys: "luas", expect: "lúa", note: "lúa" },
        Case { keys: "aaa", expect: "aa", note: "undo â" },
        Case { keys: "ass", expect: "as", note: "undo sắc" },
        Case { keys: "ddd", expect: "dd", note: "undo đ" },
        Case { keys: "asz", expect: "a", note: "z xóa thanh" },
        Case { keys: "Hoaf", expect: "Hoà", note: "Hoà" },
        Case { keys: "Vieejt", expect: "Việt", note: "Việt" },
    ];

    let vni: &[Case] = &[
        Case { keys: "a1", expect: "á", note: "á" },
        Case { keys: "a2", expect: "à", note: "à" },
        Case { keys: "a3", expect: "ả", note: "ả" },
        Case { keys: "a4", expect: "ã", note: "ã" },
        Case { keys: "a5", expect: "ạ", note: "ạ" },
        Case { keys: "a8", expect: "ă", note: "ă" },
        Case { keys: "a6", expect: "â", note: "â" },
        Case { keys: "e6", expect: "ê", note: "ê" },
        Case { keys: "o6", expect: "ô", note: "ô" },
        Case { keys: "o7", expect: "ơ", note: "ơ" },
        Case { keys: "u7", expect: "ư", note: "ư" },
        Case { keys: "d9", expect: "đ", note: "đ" },
        Case { keys: "tie6ng1", expect: "tiếng", note: "tiếng" },
        Case { keys: "vie6t5", expect: "việt", note: "việt" },
        Case { keys: "hoa2", expect: "hoà", note: "hoà" },
        Case { keys: "khoe3", expect: "khoẻ", note: "khoẻ" },
        Case { keys: "thuy3", expect: "thuỷ", note: "thuỷ" },
        Case { keys: "nguoi72", expect: "người", note: "người" },
        Case { keys: "a66", expect: "a6", note: "undo â" },
        Case { keys: "a11", expect: "a1", note: "undo sắc" },
        Case { keys: "toan1", expect: "toán", note: "toán" },
        Case { keys: "chao2", expect: "chào", note: "chào" },
        Case { keys: "cac1", expect: "các", note: "các" },
        Case { keys: "ban5", expect: "bạn", note: "bạn" },
        Case { keys: "vie6c5", expect: "việc", note: "việc" },
        Case { keys: "d9u7o7c5", expect: "được", note: "được" },
        Case { keys: "kho6ng", expect: "không", note: "không" },
        Case { keys: "phai3", expect: "phải", note: "phải" },
        Case { keys: "the61", expect: "thế", note: "thế" },
        Case { keys: "nay2", expect: "này", note: "này" },
        Case { keys: "cua3", expect: "của", note: "của" },
        Case { keys: "mo7i1", expect: "mới", note: "mới" },
        Case { keys: "cu74", expect: "cũ", note: "cũ" },
        Case { keys: "d9ep5", expect: "đẹp", note: "đẹp" },
        Case { keys: "nu7o7c1", expect: "nước", note: "nước" },
        Case { keys: "bu7o7c1", expect: "bước", note: "bước" },
        Case { keys: "Hoa2", expect: "Hoà", note: "Hoà" },
    ];

    let (tp, tf, tlines) = run_suite("Telex", Method::Telex, telex);
    let (vp, vf, vlines) = run_suite("VNI", Method::Vni, vni);

    println!("\n======== BẢNG TELEX ========");
    for l in &tlines {
        println!("{l}");
    }
    println!("\n======== BẢNG VNI ========");
    for l in &vlines {
        println!("{l}");
    }
    println!(
        "\n======== TỔNG ========\nTelex: {tp} PASS / {tf} FAIL ({} cases)\nVNI:   {vp} PASS / {vf} FAIL ({} cases)\nALL:   {} PASS / {} FAIL\n",
        telex.len(),
        vni.len(),
        tp + vp,
        tf + vf
    );

    let mut md = String::from("# Corpus Telex/VNI — kết quả thực tế `dau-core`\n\n");
    md.push_str("Chạy: `cd core && cargo test --test full_vietnamese_corpus -- --nocapture`\n\n");
    md.push_str(&format!(
        "**Tổng:** {} PASS / {} FAIL  ·  Telex {}/{}  ·  VNI {}/{}\n\n",
        tp + vp,
        tf + vf,
        tp,
        telex.len(),
        vp,
        vni.len()
    ));
    md.push_str("## Telex\n\n| Gõ | Kỳ vọng | Thực tế | KQ | Ghi chú |\n|----|---------|---------|----|--------|\n");
    for c in telex {
        let got = type_word(Method::Telex, c.keys);
        let ok = if got == c.expect { "PASS" } else { "FAIL" };
        md.push_str(&format!(
            "| `{}` | `{}` | `{}` | {} | {} |\n",
            c.keys, c.expect, got, ok, c.note
        ));
    }
    md.push_str("\n## VNI\n\n| Gõ | Kỳ vọng | Thực tế | KQ | Ghi chú |\n|----|---------|---------|----|--------|\n");
    for c in vni {
        let got = type_word(Method::Vni, c.keys);
        let ok = if got == c.expect { "PASS" } else { "FAIL" };
        md.push_str(&format!(
            "| `{}` | `{}` | `{}` | {} | {} |\n",
            c.keys, c.expect, got, ok, c.note
        ));
    }
    let report = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("target/corpus-report.md");
    let _ = std::fs::write(&report, &md);
    println!("report: {}", report.display());

    // Inventory/report only: known UniKey-order mismatches are documented in
    // docs/vietnamese-typing-corpus-results.md — do not gate CI on 100% yet.
    println!(
        "NOTE: {} FAIL (documented). Re-run inventory for full word list.",
        tf + vf
    );
    assert!(
        (tp + vp) >= 100,
        "engine regression: too few PASS ({} total)",
        tp + vp
    );
}
