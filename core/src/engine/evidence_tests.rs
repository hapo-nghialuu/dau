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
