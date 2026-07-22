//! Evidence tests for P1.5 (auto-restore + ESC) and P1.6 (shortcuts + capitalize).

use super::*;

fn type_keys(eng: &mut Engine, keys: &str) {
    for ch in keys.chars() {
        eng.process_char(ch, false);
    }
}

fn break_word(method: Method, keys: &str, brk: char) -> String {
    let mut eng = Engine::new(method);
    // Avoid start-of-stream capitalize affecting raw/commit comparisons.
    eng.set_auto_capitalize(false);
    type_keys(&mut eng, keys);
    eng.on_break(brk).text
}

// ─── Auto-restore (Telex) ─────────────────────────────────────

#[test]
fn auto_restore_english_words() {
    let cases = [
        ("text", "text"),
        ("expect", "expect"),
        ("with", "with"),
        ("wow", "wow"),
        ("perfect", "perfect"),
        ("tesla", "tesla"),
        ("student", "student"),
        ("software", "software"),
        ("keyboard", "keyboard"),
    ];
    for (keys, want) in cases {
        assert_eq!(
            break_word(Method::Telex, keys, ' '),
            want,
            "auto-restore {keys}"
        );
    }
}

#[test]
fn auto_restore_limits_mix_box_stay_vietnamese() {
    assert_eq!(break_word(Method::Telex, "mix", ' '), "mĩ");
    assert_eq!(break_word(Method::Telex, "box", ' '), "bõ");
}

#[test]
fn auto_restore_keeps_valid_vietnamese() {
    assert_eq!(break_word(Method::Telex, "tieengs", ' '), "tiếng");
    assert_eq!(break_word(Method::Telex, "vieejt", ' '), "việt");
}

/// Multi-`w` Telex for ươ/ươ* must stay Vietnamese (not raw-restored).
#[test]
fn auto_restore_keeps_uo_horn_vietnamese() {
    let cases = [
        ("truwowngf", "trường"),
        ("dduwowngf", "đường"),
        ("thuwowngr", "thưởng"),
        ("nguwowif", "người"),
        ("phuwowngf", "phường"),
        ("nuwowngs", "nướng"),
        ("cuoojc", "cuộc"),
        ("dduwowcj", "được"),
    ];
    for (keys, want) in cases {
        assert_eq!(break_word(Method::Telex, keys, ' '), want, "keep VN {keys}");
    }
}

#[test]
fn auto_restore_also_on_punctuation() {
    assert_eq!(break_word(Method::Telex, "text", '.'), "text");
    assert_eq!(break_word(Method::Telex, "with", ','), "with");
    assert_eq!(break_word(Method::Telex, "wow", '!'), "wow");
}

#[test]
fn auto_restore_can_be_disabled() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.set_auto_restore(false);
    type_keys(&mut eng, "text");
    // Without restore, composed form is kept (tẽt).
    assert_eq!(eng.on_break(' ').text, "tẽt");
}

// ─── ESC restore ──────────────────────────────────────────────

#[test]
fn escape_returns_raw_user() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_keys(&mut eng, "user");
    // Composed form has diacritics; ESC restores keystrokes.
    assert_ne!(eng.composing(), "user");
    assert_eq!(eng.escape(), "user");
    assert_eq!(eng.composing(), "user");
    assert_eq!(eng.raw(), "user");
}

#[test]
fn escape_pass_through_no_reapply() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_keys(&mut eng, "as");
    assert_eq!(eng.composing(), "á");
    assert_eq!(eng.escape(), "as");
    // Further tone key must not re-transform the restored word.
    eng.process_char('s', false);
    assert_eq!(eng.composing(), "ass");
    assert_eq!(eng.on_break(' ').text, "ass");
}

#[test]
fn escape_mix_limit_case() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_keys(&mut eng, "mix");
    assert_eq!(eng.composing(), "mĩ");
    assert_eq!(eng.escape(), "mix");
}

// ─── Shortcuts ────────────────────────────────────────────────

#[test]
fn shortcut_vn_space() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.set_shortcuts(vec![("vn".into(), "Việt Nam".into())]);
    type_keys(&mut eng, "vn");
    assert_eq!(eng.on_break(' ').text, "Việt Nam");
}

#[test]
fn shortcut_before_auto_restore() {
    // Even if raw would restore as English, shortcut wins.
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.set_shortcuts(vec![("text".into(), "văn bản".into())]);
    type_keys(&mut eng, "text");
    assert_eq!(eng.on_break(' ').text, "văn bản");
}

#[test]
fn shortcut_longest_exact_key() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.set_shortcuts(vec![
        ("ko".into(), "không".into()),
        ("k".into(), "K".into()),
        ("dc".into(), "được".into()),
    ]);
    type_keys(&mut eng, "ko");
    assert_eq!(eng.on_break(' ').text, "không");
}

// ─── Auto-capitalize ──────────────────────────────────────────

#[test]
fn capitalize_after_sentence_end() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(true);
    // Consume initial capitalize with "ok".
    type_keys(&mut eng, "ok");
    let out = eng.on_break('.');
    assert!(out.capitalize_next);
    eng.process_char('b', false);
    assert_eq!(eng.composing(), "B");
}

#[test]
fn capitalize_start_of_stream() {
    let mut eng = Engine::new(Method::Telex);
    eng.process_char('a', false);
    assert_eq!(eng.composing(), "A");
}

#[test]
fn capitalize_space_after_period_keeps_flag() {
    let mut eng = Engine::new(Method::Telex);
    type_keys(&mut eng, "ok");
    let out = eng.on_break('.');
    assert!(out.capitalize_next);
    // Space with empty buffer must not clear capitalize_next.
    let out = eng.on_break(' ');
    assert!(out.capitalize_next);
    assert_eq!(out.text, "");
    eng.process_char('b', false);
    assert_eq!(eng.composing(), "B");
}

#[test]
fn capitalize_mid_sentence_space_clears() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_keys(&mut eng, "ok");
    let out = eng.on_break(' ');
    assert!(!out.capitalize_next);
}

#[test]
fn capitalize_can_be_disabled() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.process_char('a', false);
    assert_eq!(eng.composing(), "a");
}

// ─── raw() ────────────────────────────────────────────────────

#[test]
fn raw_tracks_keystrokes() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_keys(&mut eng, "tieengs");
    assert_eq!(eng.raw(), "tieengs");
    assert_eq!(eng.composing(), "tiếng");
}

#[test]
fn on_break_does_not_include_brk() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_keys(&mut eng, "vieejt");
    let out = eng.on_break(' ');
    assert_eq!(out.text, "việt");
    assert!(!out.text.contains(' '));
    assert_eq!(eng.composing(), "");
    assert_eq!(eng.raw(), "");
}
