//! Strict blessed Vietnamese corpus loaded from static TSV fixtures.
//! Run: `cd core && cargo test --test full_vietnamese_corpus`

use std::collections::{HashMap, HashSet};

use dau_core::{Engine, Method};

const WORDS: &str = include_str!("data/blessed-vietnamese-words.tsv");
const PHRASES: &str = include_str!("data/blessed-vietnamese-phrases.tsv");

#[derive(Debug)]
struct Case<'a> {
    category: &'a str,
    expected: &'a str,
    telex: &'a str,
    vni: &'a str,
    line: usize,
}

fn parse_cases(source: &str) -> Vec<Case<'_>> {
    source
        .lines()
        .enumerate()
        .filter_map(|(index, raw)| {
            let raw = raw.trim();
            if raw.is_empty() || raw.starts_with('#') {
                return None;
            }

            let fields: Vec<_> = raw.split('\t').collect();
            assert_eq!(
                fields.len(),
                4,
                "fixture line {} must have four tab-separated fields",
                index + 1
            );
            assert!(
                fields.iter().all(|field| !field.is_empty()),
                "fixture line {} contains an empty field",
                index + 1
            );
            Some(Case {
                category: fields[0],
                expected: fields[1],
                telex: fields[2],
                vni: fields[3],
                line: index + 1,
            })
        })
        .collect()
}

fn engine(method: Method) -> Engine {
    let mut engine = Engine::new(method);
    engine.set_auto_capitalize(false);
    engine.set_auto_restore(true);
    engine
}

fn assert_word(method: Method, method_name: &str, case: &Case<'_>, keys: &str) {
    assert!(
        !keys.contains(' '),
        "{method_name} word keys contain a space at line {}",
        case.line
    );
    let mut engine = engine(method);
    for ch in keys.chars() {
        engine.process_char(ch, ch.is_ascii_uppercase());
    }

    assert_eq!(
        engine.composing(),
        case.expected,
        "{method_name} composing failed for {:?} at line {} ({})",
        keys,
        case.line,
        case.category
    );
    assert_eq!(
        engine.on_break(' ').text,
        case.expected,
        "{method_name} space commit failed for {:?} at line {} ({})",
        keys,
        case.line,
        case.category
    );
}

fn assert_phrase(method: Method, method_name: &str, case: &Case<'_>, keys: &str) {
    let raw_words: Vec<_> = keys.split_whitespace().collect();
    let expected_words: Vec<_> = case.expected.split_whitespace().collect();
    assert_eq!(
        raw_words.len(),
        expected_words.len(),
        "{method_name} phrase shape mismatch at line {}",
        case.line
    );

    let mut engine = engine(method);
    let mut committed = Vec::new();
    for (raw, expected) in raw_words.into_iter().zip(expected_words) {
        for ch in raw.chars() {
            engine.process_char(ch, ch.is_ascii_uppercase());
        }
        assert_eq!(
            engine.composing(),
            expected,
            "{method_name} phrase composing failed for {:?} at line {}",
            raw,
            case.line
        );
        let output = engine.on_break(' ').text;
        assert_eq!(
            output, expected,
            "{method_name} phrase commit failed for {:?} at line {}",
            raw, case.line
        );
        committed.push(output);
    }
    assert_eq!(
        committed.join(" "),
        case.expected,
        "{method_name} full phrase failed at line {} ({})",
        case.line,
        case.category
    );
}

#[test]
fn blessed_words_are_strict_for_telex_and_vni() {
    let cases = parse_cases(WORDS);
    assert!(
        cases.len() >= 100,
        "blessed corpus must contain at least 100 words"
    );
    let unique: HashSet<_> = cases.iter().map(|case| case.expected).collect();
    assert_eq!(
        unique.len(),
        cases.len(),
        "blessed word expectations must be distinct"
    );
    assert!(
        cases
            .iter()
            .all(|case| !case.expected.contains(' ') && case.expected.chars().count() > 1),
        "blessed word rows must contain words, not bare letters/diacritics"
    );

    for case in &cases {
        assert_word(Method::Telex, "Telex", case, case.telex);
        assert_word(Method::Vni, "VNI", case, case.vni);
    }
}

#[test]
fn blessed_phrases_are_strict_for_telex_and_vni() {
    let cases = parse_cases(PHRASES);
    assert!(
        cases.len() >= 10,
        "blessed corpus must contain at least 10 phrases"
    );
    let unique: HashSet<_> = cases.iter().map(|case| case.expected).collect();
    assert_eq!(
        unique.len(),
        cases.len(),
        "blessed phrase expectations must be distinct"
    );

    let words = parse_cases(WORDS);
    let word_keys: HashMap<_, _> = words
        .iter()
        .map(|case| (case.expected.to_lowercase(), (case.telex, case.vni)))
        .collect();
    for case in &cases {
        for ((expected, telex), vni) in case
            .expected
            .split_whitespace()
            .zip(case.telex.split_whitespace())
            .zip(case.vni.split_whitespace())
        {
            if let Some(keys) = word_keys.get(&expected.to_lowercase()) {
                assert!(
                    telex.eq_ignore_ascii_case(keys.0) && vni.eq_ignore_ascii_case(keys.1),
                    "phrase mapping drift at line {}: {expected}",
                    case.line
                );
            }
        }
        assert_phrase(Method::Telex, "Telex", case, case.telex);
        assert_phrase(Method::Vni, "VNI", case, case.vni);
    }
}
