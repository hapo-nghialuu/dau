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
fn repeat_escape_commits_composed_english() {
    for (keys, expected) in [
        ("beeen", "been"),
        ("ass", "as"),
        ("tesst", "test"),
        ("aaa", "aa"),
        ("ddd", "dd"),
        ("wwork", "work"),
    ] {
        let mut engine = engine_with(Method::Telex, keys);
        assert_eq!(engine.raw(), keys, "raw before {keys}");
        assert_eq!(engine.on_break(' ').text, expected, "commit {keys}");
    }
}

#[test]
fn repeated_telex_triggers_cover_daily_english_words() {
    for (keys, expected) in [
        ("usser", "user"),
        ("offf", "off"),
        ("terrminal", "terminal"),
        ("texxt", "text"),
        ("majjor", "major"),
        ("coool", "cool"),
    ] {
        let mut engine = engine_with(Method::Telex, keys);
        assert_eq!(engine.raw(), keys, "raw before {keys}");
        assert_eq!(engine.on_break(' ').text, expected, "commit {keys}");
    }
}

#[test]
fn telex_w_repeat_escape_restores_literal_w_prefix() {
    let mut engine = Engine::new(Method::Telex);
    engine.set_auto_capitalize(false);

    engine.process_char('w', false);
    assert_eq!(engine.composing(), "ư");

    engine.process_char('w', false);
    assert_eq!(engine.composing(), "w");
    assert_eq!(engine.on_break('.').text, "w");

    let mut engine = engine_with(Method::Telex, "wwork");
    assert_eq!(engine.composing(), "work");
    assert_eq!(engine.on_break(' ').text, "work");
}

#[test]
fn telex_z_and_caps_repeat_escape_oracles() {
    for (keys, expected) in [
        ("az", "az"),
        ("asz", "a"),
        ("aszz", "áz"),
        ("assz", "asz"),
        ("WW", "W"),
        ("AAA", "AA"),
        ("DDD", "DD"),
    ] {
        let mut engine = engine_with(Method::Telex, keys);
        assert_eq!(engine.on_break(' ').text, expected, "{keys}");
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
