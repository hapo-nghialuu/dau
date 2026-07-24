//! Evidence tests for Telex / VNI (P1 completion criteria).

use super::*;

fn type_word(method: Method, keys: &str) -> String {
    let mut eng = Engine::new(method);
    // Composition evidence is case-sensitive lowercase; disable sentence capitalize.
    eng.set_auto_capitalize(false);
    for ch in keys.chars() {
        eng.process_char(ch, false);
    }
    eng.composing()
}

// ─── Telex evidence ───────────────────────────────────────────

#[test]
fn telex_tieengs() {
    assert_eq!(type_word(Method::Telex, "tieengs"), "tiếng");
}

#[test]
fn telex_viet() {
    assert_eq!(type_word(Method::Telex, "viet"), "viet");
}

#[test]
fn telex_vieejt() {
    assert_eq!(type_word(Method::Telex, "vieejt"), "việt");
}

#[test]
fn telex_dd() {
    assert_eq!(type_word(Method::Telex, "dd"), "đ");
}

#[test]
fn telex_hoaf() {
    assert_eq!(type_word(Method::Telex, "hoaf"), "hoà");
}

#[test]
fn telex_khoer() {
    assert_eq!(type_word(Method::Telex, "khoer"), "khoẻ");
}

#[test]
fn telex_thuyr() {
    assert_eq!(type_word(Method::Telex, "thuyr"), "thuỷ");
}

#[test]
fn telex_nguoiwf() {
    assert_eq!(type_word(Method::Telex, "nguoiwf"), "người");
}

#[test]
fn telex_aa() {
    assert_eq!(type_word(Method::Telex, "aa"), "â");
}

#[test]
fn telex_aaa() {
    assert_eq!(type_word(Method::Telex, "aaa"), "aa");
}

#[test]
fn telex_as() {
    assert_eq!(type_word(Method::Telex, "as"), "á");
}

#[test]
fn telex_ass() {
    assert_eq!(type_word(Method::Telex, "ass"), "as");
}

#[test]
fn telex_ddd() {
    assert_eq!(type_word(Method::Telex, "ddd"), "dd");
}

#[test]
fn telex_asz() {
    assert_eq!(type_word(Method::Telex, "asz"), "a");
}

#[test]
fn telex_aw() {
    assert_eq!(type_word(Method::Telex, "aw"), "ă");
}

// ─── ua + w → ưa (not uă); TG-01 ──────────────────────────────

#[test]
fn telex_uaw_duaw_dduaw() {
    assert_eq!(type_word(Method::Telex, "uaw"), "ưa");
    assert_eq!(type_word(Method::Telex, "duaw"), "dưa");
    assert_eq!(type_word(Method::Telex, "dduaw"), "đưa");
}

#[test]
fn telex_dduaw_stepwise() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    let steps = [
        ('d', "d"),
        ('d', "đ"),
        ('u', "đu"),
        ('a', "đua"),
        ('w', "đưa"),
    ];
    for (ch, expect) in steps {
        eng.process_char(ch, false);
        assert_eq!(eng.composing(), expect, "after key `{ch}`");
    }
    // Never surface / commit suffix uă
    assert!(!eng.composing().contains('ă'));
    assert_eq!(eng.on_break(' ').text, "đưa");
}

#[test]
fn telex_dduwa_stepwise() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    let steps = [
        ('d', "d"),
        ('d', "đ"),
        ('u', "đu"),
        ('w', "đư"),
        ('a', "đưa"),
    ];
    for (ch, expect) in steps {
        eng.process_char(ch, false);
        assert_eq!(eng.composing(), expect, "after key `{ch}`");
    }
    assert_eq!(eng.on_break(' ').text, "đưa");
}

#[test]
fn telex_dduaw_never_u_breve() {
    // Transition table: no path should leave composing as *uă.
    assert_eq!(type_word(Method::Telex, "uaw"), "ưa");
    assert_ne!(type_word(Method::Telex, "uaw"), "uă");
    assert_ne!(type_word(Method::Telex, "duaw"), "duă");
    assert_ne!(type_word(Method::Telex, "dduaw"), "đuă");
}

// ─── Tone placement regression (closed glide clusters) ────────

#[test]
fn telex_toans() {
    // Closed oa → tone on a (not o): toán
    assert_eq!(type_word(Method::Telex, "toans"), "toán");
}

#[test]
fn telex_hoas() {
    // Open oa → tone on a: hoá
    assert_eq!(type_word(Method::Telex, "hoas"), "hoá");
}

#[test]
fn telex_quawms() {
    // aw→ă, closed → tone on ă: quắm
    assert_eq!(type_word(Method::Telex, "quawms"), "quắm");
}

#[test]
fn telex_ngoaif() {
    // Open 3-vowel oai → middle a: ngoài
    assert_eq!(type_word(Method::Telex, "ngoaif"), "ngoài");
}

#[test]
fn telex_tuaan() {
    // uâ: mark on â → tone on â: tuân
    assert_eq!(type_word(Method::Telex, "tuaan"), "tuân");
}

#[test]
fn telex_khoawns() {
    // aw→ă + final n + sắc → khoắn
    assert_eq!(type_word(Method::Telex, "khoawns"), "khoắn");
}

// ─── VNI evidence ─────────────────────────────────────────────

#[test]
fn vni_tie6ng1() {
    assert_eq!(type_word(Method::Vni, "tie6ng1"), "tiếng");
}

#[test]
fn vni_vie6t5() {
    assert_eq!(type_word(Method::Vni, "vie6t5"), "việt");
}

#[test]
fn vni_hoa2() {
    assert_eq!(type_word(Method::Vni, "hoa2"), "hoà");
}

#[test]
fn vni_khoe3() {
    assert_eq!(type_word(Method::Vni, "khoe3"), "khoẻ");
}

#[test]
fn vni_thuy3() {
    assert_eq!(type_word(Method::Vni, "thuy3"), "thuỷ");
}

#[test]
fn vni_nguoi72() {
    assert_eq!(type_word(Method::Vni, "nguoi72"), "người");
}

#[test]
fn vni_a66() {
    assert_eq!(type_word(Method::Vni, "a66"), "a6");
}

#[test]
fn vni_a11() {
    assert_eq!(type_word(Method::Vni, "a11"), "a1");
}

#[test]
fn vni_toan1() {
    assert_eq!(type_word(Method::Vni, "toan1"), "toán");
}

#[test]
fn vni_hoa1() {
    assert_eq!(type_word(Method::Vni, "hoa1"), "hoá");
}

// ─── Validation ───────────────────────────────────────────────

#[test]
fn validation_zzs() {
    assert_eq!(type_word(Method::Telex, "zzs"), "zzs");
}

#[test]
fn validation_btw() {
    let out = type_word(Method::Telex, "btw");
    // Spec: giữ thô — không crash, không tạo dấu sai luật.
    assert_eq!(out, "btw");
}

#[test]
fn clear_resets() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.process_char('a', false);
    eng.process_char('s', false);
    assert_eq!(eng.composing(), "á");
    eng.clear();
    assert_eq!(eng.composing(), "");
}

#[test]
fn set_method_switches() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.set_method(Method::Vni);
    eng.process_char('a', false);
    eng.process_char('1', false);
    assert_eq!(eng.composing(), "á");
}

// ─── Backspace one display scalar (TG-03) ─────────────────────

fn type_into(eng: &mut Engine, keys: &str) {
    for ch in keys.chars() {
        eng.process_char(ch, false);
    }
}

#[test]
fn backspace_telex_dduwa_then_retype() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_into(&mut eng, "dduwa");
    assert_eq!(eng.composing(), "đưa");

    assert_eq!(eng.backspace_one_display_scalar(), Some("đư".into()));
    assert_eq!(eng.composing(), "đư");

    eng.process_char('a', false);
    assert_eq!(eng.composing(), "đưa");
}

#[test]
fn backspace_telex_dduaw_same_as_dduwa() {
    // Same visible sequence as dduwa when TG-01 `ua+w` is active.
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_into(&mut eng, "dduaw");
    assert_eq!(eng.composing(), "đưa");
    assert_eq!(eng.backspace_one_display_scalar(), Some("đư".into()));
    eng.process_char('a', false);
    assert_eq!(eng.composing(), "đưa");
}

#[test]
fn backspace_telex_tieengs_then_retype() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_into(&mut eng, "tieengs");
    assert_eq!(eng.composing(), "tiếng");

    assert_eq!(eng.backspace_one_display_scalar(), Some("tiến".into()));
    eng.process_char('g', false);
    assert_eq!(eng.composing(), "tiếng");
}

#[test]
fn backspace_vni_tie6ng1_then_retype() {
    let mut eng = Engine::new(Method::Vni);
    eng.set_auto_capitalize(false);
    type_into(&mut eng, "tie6ng1");
    assert_eq!(eng.composing(), "tiếng");

    assert_eq!(eng.backspace_one_display_scalar(), Some("tiến".into()));
    eng.process_char('g', false);
    assert_eq!(eng.composing(), "tiếng");
}

#[test]
fn backspace_english_delete_then_retype() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    eng.set_auto_restore(true);
    type_into(&mut eng, "delete");
    assert_eq!(eng.composing(), "delete");

    assert_eq!(eng.backspace_one_display_scalar(), Some("delet".into()));
    eng.process_char('e', false);
    assert_eq!(eng.composing(), "delete");
    assert_eq!(eng.on_break(' ').text, "delete");
}

#[test]
fn backspace_aa_removes_one_display_unit() {
    // `aa` → `â` is one visible scalar; backspace must clear fully (not leave raw `a`).
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_into(&mut eng, "aa");
    assert_eq!(eng.composing(), "â");
    assert_eq!(eng.backspace_one_display_scalar(), Some(String::new()));
    assert_eq!(eng.composing(), "");
    assert_eq!(eng.raw(), "");
}

#[test]
fn backspace_empty_is_none() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    assert_eq!(eng.backspace_one_display_scalar(), None);
    assert_eq!(eng.composing(), "");
}

#[test]
fn backspace_repeated_to_empty_then_none() {
    let mut eng = Engine::new(Method::Telex);
    eng.set_auto_capitalize(false);
    type_into(&mut eng, "ab");
    assert_eq!(eng.backspace_one_display_scalar(), Some("a".into()));
    assert_eq!(eng.backspace_one_display_scalar(), Some(String::new()));
    assert_eq!(eng.backspace_one_display_scalar(), None);
    assert_eq!(eng.backspace_one_display_scalar(), None);
}
