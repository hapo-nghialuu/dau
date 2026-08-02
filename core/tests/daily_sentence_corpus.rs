//! Daily sentence corpus: English + Vietnamese while Vietnamese IME is active.
//!
//! The fixture is intentionally sentence-based and non-repeated. This prevents
//! the regression fixture from becoming a bag of isolated word pairs or a small
//! set of rows multiplied into a large-looking corpus.

use dau_core::{Engine, Method};
use std::collections::HashSet;

const FIXTURE: &str = include_str!("data/daily-english-vietnamese-sentences.tsv");
const MIN_EXPANDED_TOKENS: usize = 1000;
const MIN_UNIQUE_ROWS: usize = 100;

#[derive(Debug)]
struct Row<'a> {
    telex: &'a str,
    vni: &'a str,
    expected: &'a str,
}

fn rows() -> Vec<Row<'static>> {
    FIXTURE
        .lines()
        .enumerate()
        .filter(|(_, line)| {
            let trimmed = line.trim();
            !trimmed.is_empty() && !trimmed.starts_with('#')
        })
        .map(|(index, line)| {
            let parts: Vec<_> = line.split('\t').collect();
            assert_eq!(
                parts.len(),
                3,
                "fixture line {} must have 3 TSV fields",
                index + 1
            );
            Row {
                telex: parts[0],
                vni: parts[1],
                expected: parts[2],
            }
        })
        .collect()
}

fn alphabetic_token_count(text: &str) -> usize {
    text.split(|ch: char| !ch.is_alphabetic())
        .filter(|token| !token.is_empty())
        .count()
}

fn assert_sentence_like(row: &Row<'_>, index: usize) {
    assert!(
        row.expected.contains(char::is_whitespace),
        "row {index} must be a sentence, not a single token"
    );
    assert!(
        alphabetic_token_count(row.expected) >= 5,
        "row {index} must contain at least five alphabetic tokens"
    );
    assert!(
        row.expected.ends_with(['.', '!', '?']),
        "row {index} should include sentence punctuation"
    );
}

fn type_text(method: Method, keys: &str) -> String {
    let mut engine = Engine::new(method);
    engine.set_auto_capitalize(false);
    engine.set_auto_restore(true);

    let mut output = String::new();
    for ch in keys.chars() {
        if ch.is_ascii_alphanumeric() {
            engine.process_char(ch, ch.is_ascii_uppercase());
        } else {
            output.push_str(&engine.on_break(ch).text);
            output.push(ch);
        }
    }
    output
}

#[test]
fn daily_english_vietnamese_sentences_round_trip_with_ime_active() {
    let rows = rows();
    assert!(!rows.is_empty(), "daily sentence fixture must not be empty");
    assert!(
        rows.len() >= MIN_UNIQUE_ROWS,
        "daily sentence fixture must contain at least {MIN_UNIQUE_ROWS} rows, got {}",
        rows.len()
    );

    let mut seen = HashSet::new();
    for (index, row) in rows.iter().enumerate() {
        assert!(
            seen.insert(row.expected),
            "duplicate expected_text at row {}: {}",
            index + 1,
            row.expected
        );
    }

    let mut expanded_tokens = 0usize;
    for (index, row) in rows.iter().enumerate() {
        assert_sentence_like(row, index + 1);
        expanded_tokens += alphabetic_token_count(row.expected);

        let telex = type_text(Method::Telex, row.telex);
        assert_eq!(telex, row.expected, "Telex row {}", index + 1);

        let vni = type_text(Method::Vni, row.vni);
        assert_eq!(vni, row.expected, "VNI row {}", index + 1);
    }

    assert!(
        expanded_tokens >= MIN_EXPANDED_TOKENS,
        "expanded fixture must cover at least {MIN_EXPANDED_TOKENS} alphabetic tokens, got {expanded_tokens}"
    );
    println!(
        "DAILY_SENTENCE_CORPUS tokens={expanded_tokens} rows={}",
        rows.len()
    );
}
