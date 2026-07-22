//! Telex key → transformation actions.

use crate::engine::buffer::{Buffer, CompChar};
use crate::engine::syllable::is_valid_syllable;
use crate::engine::tone::{self, Mark, Tone};
use crate::engine::util::{find_rightmost, find_uo_pair};

/// Process one Telex key into `buf`.
pub fn process(buf: &mut Buffer, key: char, caps: bool) -> String {
    let k = key.to_ascii_lowercase();

    if let Some(tone) = tone_key(k) {
        try_tone(buf, tone, k, caps);
        return buf.display();
    }

    match k {
        'a' => try_circumflex_or_append(buf, 'a', caps),
        'e' => try_circumflex_or_append(buf, 'e', caps),
        'o' => try_circumflex_or_append(buf, 'o', caps),
        'w' => try_w(buf, caps),
        'd' => try_stroke_d(buf, caps),
        _ => buf.push(CompChar::new(k, caps)),
    }
    buf.display()
}

fn tone_key(k: char) -> Option<Tone> {
    match k {
        's' => Some(Tone::Acute),
        'f' => Some(Tone::Grave),
        'r' => Some(Tone::Hook),
        'x' => Some(Tone::Tilde),
        'j' => Some(Tone::Dot),
        'z' => Some(Tone::None),
        _ => None,
    }
}

fn try_tone(buf: &mut Buffer, tone: Tone, raw_key: char, caps: bool) {
    if buf.is_empty() {
        buf.push(CompChar::new(raw_key, caps));
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
        buf.push(CompChar::new(raw_key, caps));
        return;
    }

    // Double-key: same tone already present → strip + append raw.
    if cur == tone {
        tone::strip_tone(buf);
        buf.push(CompChar::new(raw_key, caps));
        return;
    }

    if !tone::apply_tone(buf, tone) {
        buf.restore(snap);
        buf.push(CompChar::new(raw_key, caps));
        return;
    }

    if !is_valid_syllable(buf) {
        buf.restore(snap);
        buf.push(CompChar::new(raw_key, caps));
    }
}

/// aa→â, ee→ê, oo→ô; double-key aaa→aa.
fn try_circumflex_or_append(buf: &mut Buffer, letter: char, caps: bool) {
    if let Some(i) = find_rightmost(buf, |c| {
        c.base == letter && (c.mark == Mark::None || c.mark == Mark::Circumflex)
    }) {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Circumflex {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            buf.push(CompChar::new(letter, caps));
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
    buf.push(CompChar::new(letter, caps));
}

/// w: uw→ư, ow→ơ, uo+w→ươ, bare w→ư; double-key reverts.
fn try_w(buf: &mut Buffer, caps: bool) {
    if buf.is_empty() {
        let mut c = CompChar::new('u', caps);
        c.mark = Mark::Horn;
        buf.push(c);
        return;
    }

    let snap = buf.snapshot();

    // Double-key when horn already applied and no further w-action fits.
    if let Some(i) = find_rightmost(buf, |c| c.mark == Mark::Horn) {
        if !can_apply_uo_w(buf) && !can_apply_simple_w(buf) {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            strip_paired_horn(buf);
            buf.push(CompChar::new('w', caps));
            return;
        }
    }

    if apply_uo_w(buf) {
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap.clone());
    }

    // aw → ă
    if let Some(i) = find_rightmost(buf, |c| c.base == 'a' && c.mark == Mark::None) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Breve;
        }
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap.clone());
    }

    // ow → ơ
    if let Some(i) = find_rightmost(buf, |c| c.base == 'o' && c.mark == Mark::None) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Horn;
        }
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap.clone());
    }

    // uw → ư
    if let Some(i) = find_rightmost(buf, |c| c.base == 'u' && c.mark == Mark::None) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Horn;
        }
        if is_valid_syllable(buf) {
            return;
        }
        buf.restore(snap.clone());
    }

    if let Some(i) = find_rightmost(buf, |c| c.mark == Mark::Horn) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::None;
        }
        strip_paired_horn(buf);
        buf.push(CompChar::new('w', caps));
        return;
    }

    let mut c = CompChar::new('u', caps);
    c.mark = Mark::Horn;
    buf.push(c);
    if is_valid_syllable(buf) {
        return;
    }
    buf.restore(snap);
    buf.push(CompChar::new('w', caps));
}

fn can_apply_uo_w(buf: &Buffer) -> bool {
    find_uo_pair(buf).is_some_and(|(i, j)| {
        let chars = buf.chars();
        chars[i].mark == Mark::None && chars[j].mark == Mark::None
    })
}

fn can_apply_simple_w(buf: &Buffer) -> bool {
    find_rightmost(buf, |c| {
        matches!(c.base, 'a' | 'o' | 'u') && c.mark == Mark::None
    })
    .is_some()
}

fn apply_uo_w(buf: &mut Buffer) -> bool {
    if let Some((i, j)) = find_uo_pair(buf) {
        let chars = buf.chars();
        if chars[i].mark != Mark::None || chars[j].mark != Mark::None {
            return false;
        }
        if let Some(u) = buf.get_mut(i) {
            u.mark = Mark::Horn;
        }
        if let Some(o) = buf.get_mut(j) {
            o.mark = Mark::Horn;
        }
        return true;
    }
    false
}

fn strip_paired_horn(buf: &mut Buffer) {
    let chars = buf.chars().to_vec();
    for i in 0..chars.len() {
        if chars[i].base == 'u' && chars[i].mark == Mark::Horn {
            if let Some(c2) = chars.get(i + 1) {
                if c2.base == 'o' && c2.mark == Mark::Horn {
                    if let Some(u) = buf.get_mut(i) {
                        u.mark = Mark::None;
                    }
                    if let Some(o) = buf.get_mut(i + 1) {
                        o.mark = Mark::None;
                    }
                    return;
                }
            }
        }
    }
}

/// dd→đ; ddd→dd.
fn try_stroke_d(buf: &mut Buffer, caps: bool) {
    if let Some(i) = find_rightmost(buf, |c| c.base == 'd') {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Stroke {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            buf.push(CompChar::new('d', caps));
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
    buf.push(CompChar::new('d', caps));
}
