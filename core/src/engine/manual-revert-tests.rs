use super::*;

fn type_keys(engine: &mut Engine, keys: &str) {
    for ch in keys.chars() {
        engine.process_char(ch, false);
    }
}

fn engine_with(method: Method, keys: &str) -> Engine {
    let mut engine = Engine::new(method);
    engine.set_auto_capitalize(false);
    type_keys(&mut engine, keys);
    engine
}

#[test]
fn tesst_auto_restore_keeps_composed_telex_on_supported_breaks() {
    for brk in [' ', '.', ',', '!', '?', '\n', ';', ':'] {
        let mut engine = engine_with(Method::Telex, "tesst");
        assert_eq!(engine.raw(), "tesst", "raw before {brk:?}");
        assert_eq!(engine.composing(), "test", "composing before {brk:?}");
        assert_eq!(engine.on_break(brk).text, "test", "commit on {brk:?}");
    }
}

#[test]
fn common_english_words_with_telex_control_keys_commit_raw() {
    for keys in [
        "will",
        "watt",
        "coffee",
        "effect",
        "class",
        "chessboard",
        "crossfit",
        "off",
        "errs",
        "cliffs",
        "address",
        "different",
        "offer",
        "staff",
        "grass",
        "press",
        "issue",
        "success",
        "message",
        "error",
        "array",
        "book",
        "feel",
    ] {
        let mut engine = engine_with(Method::Telex, keys);
        if matches!(keys, "coffee" | "effect" | "off" | "errs") {
            assert_ne!(engine.composing(), keys, "restore precondition {keys}");
        }
        assert_eq!(engine.on_break(' ').text, keys, "commit {keys}");
    }
}

#[test]
fn manual_revert_handles_punctuation_caps_and_reset() {
    let mut engine = engine_with(Method::Telex, "Tesst");
    assert_eq!(engine.composing(), "Test");
    assert_eq!(engine.on_break('.').text, "Test");

    let mut engine = engine_with(Method::Telex, "tesst");
    engine.set_auto_restore(false);
    assert_eq!(engine.on_break(' ').text, "test");

    let mut engine = engine_with(Method::Telex, "tesst");
    engine.clear();
    type_keys(&mut engine, "text");
    assert_eq!(engine.on_break(' ').text, "text");
}

#[test]
fn escape_after_manual_revert_returns_exact_raw_keys() {
    let mut engine = engine_with(Method::Telex, "tesst");

    assert_eq!(engine.composing(), "test");
    assert_eq!(engine.escape(), "tesst");
    assert_eq!(engine.on_break(' ').text, "tesst");
}

#[test]
fn english_auto_restore_and_vietnamese_commit_remain_unchanged() {
    for (keys, expected) in [("text", "text"), ("wow", "wow")] {
        let mut engine = engine_with(Method::Telex, keys);
        assert_eq!(engine.on_break(' ').text, expected, "{keys}");
    }

    let mut engine = engine_with(Method::Telex, "tieengs");
    assert_eq!(engine.on_break(' ').text, "tiếng");

    let mut engine = engine_with(Method::Vni, "tesst");
    assert_eq!(engine.composing(), "tesst");
    assert_eq!(engine.on_break(' ').text, "tesst");

    for keys in ["a11", "a1n1", "d99"] {
        let mut engine = engine_with(Method::Vni, keys);
        assert_eq!(engine.on_break(' ').text, keys, "VNI compatibility {keys}");
    }
}
