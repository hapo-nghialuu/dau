//! VNI key → transformation actions.

use crate::engine::buffer::{Buffer, CompChar};
use crate::engine::syllable::is_valid_syllable;
use crate::engine::tone::{self, Mark, Tone};
use crate::engine::util::{find_rightmost, find_uo_pair};

/// Process one VNI key into `buf`.
pub fn process(buf: &mut Buffer, key: char, caps: bool) -> String {
    match key {
        '1' => try_tone(buf, Tone::Acute, '1', caps),
        '2' => try_tone(buf, Tone::Grave, '2', caps),
        '3' => try_tone(buf, Tone::Hook, '3', caps),
        '4' => try_tone(buf, Tone::Tilde, '4', caps),
        '5' => try_tone(buf, Tone::Dot, '5', caps),
        '0' => try_tone(buf, Tone::None, '0', caps),
        '6' => try_circumflex(buf, caps),
        '7' => try_horn(buf, caps),
        '8' => try_breve(buf, caps),
        '9' => try_stroke(buf, caps),
        ch if ch.is_ascii_alphabetic() => {
            buf.push(CompChar::new(
                ch.to_ascii_lowercase(),
                caps || ch.is_ascii_uppercase(),
            ));
        }
        ch => push_raw(buf, ch, caps),
    }
    buf.display()
}

fn try_tone(buf: &mut Buffer, tone: Tone, raw: char, caps: bool) {
    if buf.is_empty() {
        push_raw(buf, raw, caps);
        return;
    }

    let snap = buf.snapshot();
    let cur = tone::current_tone(buf);

    if tone == Tone::None {
        if cur != Tone::None {
            tone::strip_tone(buf);
            if is_valid_syllable(buf) {
                return;
            }
            buf.restore(snap);
        }
        push_raw(buf, raw, caps);
        return;
    }

    if cur == tone {
        tone::strip_tone(buf);
        push_raw(buf, raw, caps);
        return;
    }

    if !tone::apply_tone(buf, tone) {
        buf.restore(snap);
        push_raw(buf, raw, caps);
        return;
    }

    if !is_valid_syllable(buf) {
        buf.restore(snap);
        push_raw(buf, raw, caps);
    }
}

/// a6→â, e6→ê, o6→ô; a66→a6.
fn try_circumflex(buf: &mut Buffer, caps: bool) {
    if let Some(i) = find_rightmost(buf, |c| {
        matches!(c.base, 'a' | 'e' | 'o') && (c.mark == Mark::None || c.mark == Mark::Circumflex)
    }) {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Circumflex {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            push_raw(buf, '6', caps);
            return;
        }
        let snap = buf.snapshot();
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Circumflex;
        }
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap);
    }
    push_raw(buf, '6', caps);
}

/// o7→ơ, u7→ư; uo+7→ươ; double-key reverts.
fn try_horn(buf: &mut Buffer, caps: bool) {
    let snap = buf.snapshot();

    if let Some((i, j)) = find_uo_pair(buf) {
        let u = buf.get(i).unwrap();
        let o = buf.get(j).unwrap();
        if u.mark == Mark::Horn && o.mark == Mark::Horn {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            if let Some(ch) = buf.get_mut(j) {
                ch.mark = Mark::None;
            }
            push_raw(buf, '7', caps);
            return;
        }
        if u.mark == Mark::None && o.mark == Mark::None {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::Horn;
            }
            if let Some(ch) = buf.get_mut(j) {
                ch.mark = Mark::Horn;
            }
            if is_valid_syllable(buf) {
                return;
            }
            buf.restore(snap.clone());
        }
    }

    if let Some(i) = find_rightmost(buf, |c| {
        matches!(c.base, 'o' | 'u') && (c.mark == Mark::None || c.mark == Mark::Horn)
    }) {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Horn {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            push_raw(buf, '7', caps);
            return;
        }
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Horn;
        }
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap);
    }

    push_raw(buf, '7', caps);
}

/// a8→ă
fn try_breve(buf: &mut Buffer, caps: bool) {
    if let Some(i) = find_rightmost(buf, |c| {
        c.base == 'a' && (c.mark == Mark::None || c.mark == Mark::Breve)
    }) {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Breve {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            push_raw(buf, '8', caps);
            return;
        }
        let snap = buf.snapshot();
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Breve;
        }
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap);
    }
    push_raw(buf, '8', caps);
}

/// d9→đ
fn try_stroke(buf: &mut Buffer, caps: bool) {
    if let Some(i) = find_rightmost(buf, |c| c.base == 'd') {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Stroke {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            push_raw(buf, '9', caps);
            return;
        }
        let snap = buf.snapshot();
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Stroke;
        }
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap);
    }
    push_raw(buf, '9', caps);
}

/// Append raw digit/symbol so double-key revert displays (e.g. a66→a6).
fn push_raw(buf: &mut Buffer, d: char, caps: bool) {
    buf.push(CompChar::new(d, caps));
}
