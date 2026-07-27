//! Round-trip investigation corpus: canonical Vietnamese → independent Telex/VNI keys.

use dau_core::{Engine, Method};

const CORPUS: &str = include_str!("data/common_vietnamese_syllables_top_2000.txt");

fn corpus_words() -> Vec<&'static str> {
    CORPUS.lines().collect()
}

fn base_keys(ch: char, method: Method) -> Option<String> {
    let (telex, vni) = match ch {
        'a' | 'á' | 'à' | 'ả' | 'ã' | 'ạ' => ("a", "a"),
        'ă' | 'ắ' | 'ằ' | 'ẳ' | 'ẵ' | 'ặ' => ("aw", "a8"),
        'â' | 'ấ' | 'ầ' | 'ẩ' | 'ẫ' | 'ậ' => ("aa", "a6"),
        'e' | 'é' | 'è' | 'ẻ' | 'ẽ' | 'ẹ' => ("e", "e"),
        'ê' | 'ế' | 'ề' | 'ể' | 'ễ' | 'ệ' => ("ee", "e6"),
        'i' | 'í' | 'ì' | 'ỉ' | 'ĩ' | 'ị' => ("i", "i"),
        'o' | 'ó' | 'ò' | 'ỏ' | 'õ' | 'ọ' => ("o", "o"),
        'ô' | 'ố' | 'ồ' | 'ổ' | 'ỗ' | 'ộ' => ("oo", "o6"),
        'ơ' | 'ớ' | 'ờ' | 'ở' | 'ỡ' | 'ợ' => ("ow", "o7"),
        'u' | 'ú' | 'ù' | 'ủ' | 'ũ' | 'ụ' => ("u", "u"),
        'ư' | 'ứ' | 'ừ' | 'ử' | 'ữ' | 'ự' => ("uw", "u7"),
        'y' | 'ý' | 'ỳ' | 'ỷ' | 'ỹ' | 'ỵ' => ("y", "y"),
        'đ' => ("dd", "d9"),
        ch if ch.is_ascii_alphabetic() => return Some(ch.to_string()),
        _ => return None,
    };
    Some(if method == Method::Telex { telex } else { vni }.to_string())
}

fn tone_key(ch: char, method: Method) -> Option<char> {
    let telex = if "áắấéếíóốớúứý".contains(ch) {
        's'
    } else if "àằầèềìòồờùừỳ".contains(ch) {
        'f'
    } else if "ảẳẩẻểỉỏổởủửỷ".contains(ch) {
        'r'
    } else if "ãẵẫẽễĩõỗỡũữỹ".contains(ch) {
        'x'
    } else if "ạặậẹệịọộợụựỵ".contains(ch) {
        'j'
    } else {
        return None;
    };
    Some(if method == Method::Telex {
        telex
    } else {
        match telex {
            's' => '1',
            'f' => '2',
            'r' => '3',
            'x' => '4',
            'j' => '5',
            _ => unreachable!(),
        }
    })
}

/// Independent oracle: Unicode spelling tables above, not engine internals.
fn encode(word: &str, method: Method) -> String {
    let mut keys = String::new();
    let mut tone = None;
    for ch in word.chars() {
        keys.push_str(
            &base_keys(ch, method).unwrap_or_else(|| panic!("unsupported corpus char {ch:?}")),
        );
        tone = tone.or_else(|| tone_key(ch, method));
    }
    if let Some(mark) = tone {
        keys.push(mark);
    }
    keys
}

fn type_until_space(method: Method, keys: &str) -> (String, String) {
    let mut engine = Engine::new(method);
    engine.set_auto_capitalize(false);
    engine.set_auto_restore(true);
    for ch in keys.chars() {
        engine.process_char(ch, false);
    }
    let display = engine.composing();
    let committed = engine.on_break(' ').text;
    (display, committed)
}

fn method_name(method: Method) -> &'static str {
    match method {
        Method::Telex => "Telex",
        Method::Vni => "VNI",
    }
}

/// Known gaps theo quyết định sản phẩm 2026-07-26: coda `k` (địa danh Tây Nguyên
/// gốc Ê Đê như Đắk Lắk) nằm ngoài chuẩn âm tiết tiếng Việt, chưa hỗ trợ.
/// Mục ở đây vẫn phải FAIL thật — nếu engine bắt đầu gõ được thì test đỏ,
/// buộc xoá khỏi danh sách (chống mục nát known-gap).
const KNOWN_GAPS: &[&str] = &["đắk", "lắk"];

fn is_known_gap(word: &str) -> bool {
    KNOWN_GAPS.contains(&word)
}

fn investigate_words(words: &[&str], method: Method, failures: &mut Vec<String>) -> usize {
    let mut pass = 0;
    for (index, &expect) in words.iter().enumerate() {
        let keys = encode(expect, method);
        let (display, committed) = type_until_space(method, &keys);
        let ok = display == expect && committed == expect;
        if is_known_gap(expect) {
            if ok {
                failures.push(format!(
                    "GAP NOW PASSES | {}#{index} | `{expect}` đã gõ được — xoá khỏi KNOWN_GAPS",
                    method_name(method)
                ));
            } else {
                println!(
                    "SKIP-KNOWN | {}#{index} | `{expect}` (coda k ngoài chuẩn)",
                    method_name(method)
                );
                pass += 1;
            }
            continue;
        }
        if ok {
            pass += 1;
        } else {
            failures.push(format!(
                "WORD FAIL | {}#{index} | kỳ vọng `{expect}` | phím `{keys}` | display `{display}` | commit `{committed}`",
                method_name(method)
            ));
        }
    }
    pass
}

fn investigate_continuous(words: &[&str], method: Method, failures: &mut Vec<String>) -> bool {
    let mut engine = Engine::new(method);
    engine.set_auto_capitalize(false);
    engine.set_auto_restore(true);
    let mut actual = String::new();
    let mut expected_parts: Vec<String> = Vec::with_capacity(words.len());
    let mut word_failures = 0;
    for (index, &expect) in words.iter().enumerate() {
        let keys = encode(expect, method);
        for ch in keys.chars() {
            engine.process_char(ch, false);
        }
        let committed = engine.on_break(' ').text;
        actual.push_str(&committed);
        actual.push(' ');
        if committed != expect {
            if is_known_gap(expect) {
                // Known gap: giữ nguyên output thật trong expected để whole-text
                // so khớp phần còn lại; không tính là failure.
                expected_parts.push(committed.clone());
                continue;
            }
            word_failures += 1;
            failures.push(format!(
                "CONTINUOUS WORD FAIL | {}#{index} | kỳ vọng `{expect}` | phím `{keys}` | thực tế `{committed}`",
                method_name(method)
            ));
            expected_parts.push(expect.to_string());
        } else {
            if is_known_gap(expect) {
                failures.push(format!(
                    "GAP NOW PASSES (continuous) | {}#{index} | `{expect}` — xoá khỏi KNOWN_GAPS",
                    method_name(method)
                ));
            }
            expected_parts.push(expect.to_string());
        }
    }
    let expected = format!("{} ", expected_parts.join(" "));
    let whole_pass = actual == expected;
    println!(
        "CONTINUOUS {} | words={} | PASS={} | FAIL={} | whole_text={}",
        method_name(method),
        words.len(),
        words.len() - word_failures,
        word_failures,
        if whole_pass { "PASS" } else { "FAIL" }
    );
    whole_pass
}

#[test]
fn round_trip_top_2000_vietnamese_corpus() {
    let words = corpus_words();
    assert_eq!(words.len(), 2000, "corpus size must remain exactly 2000");
    assert!(
        words.iter().all(|word| !word.trim().is_empty()),
        "corpus must not contain blank entries"
    );
    assert_eq!(
        words
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        words.len(),
        "corpus must not duplicate entries"
    );

    let mut failures = Vec::new();
    let telex_pass = investigate_words(&words, Method::Telex, &mut failures);
    let vni_pass = investigate_words(&words, Method::Vni, &mut failures);
    let telex_whole = investigate_continuous(&words, Method::Telex, &mut failures);
    let vni_whole = investigate_continuous(&words, Method::Vni, &mut failures);

    println!(
        "SUMMARY | words={} | Telex={} PASS / {} FAIL | VNI={} PASS / {} FAIL | continuous Telex={} | continuous VNI={}",
        words.len(),
        telex_pass,
        words.len() - telex_pass,
        vni_pass,
        words.len() - vni_pass,
        if telex_whole { "PASS" } else { "FAIL" },
        if vni_whole { "PASS" } else { "FAIL" },
    );
    for failure in &failures {
        println!("{failure}");
    }
    assert!(
        telex_whole && vni_whole,
        "continuous whole-text assertion failed: Telex={}, VNI={}",
        telex_whole,
        vni_whole
    );
    assert!(
        failures.is_empty(),
        "investigation failures: {}",
        failures.len()
    );
}
