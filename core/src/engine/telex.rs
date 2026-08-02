//! Telex key → transformation actions.

use crate::engine::buffer::{Buffer, CompChar};
use crate::engine::syllable::is_valid_syllable;
use crate::engine::tone::{self, Mark, Tone};
use crate::engine::util::{find_rightmost, find_uo_pair};

/// Outcome of one Telex key processing step.
///
/// `Transformed` means the buffer changed (mark/tone/appended in a way that
/// applied Vietnamese composition); `Literal` means the key appended as a raw
/// character (or a no-op append) without a Vietnamese transform. The Engine
/// uses this signal to record a pending-escape snapshot.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    Transformed,
    Literal,
}

/// Process one Telex key into `buf`.
pub fn process(buf: &mut Buffer, key: char, caps: bool) -> Outcome {
    let k = key.to_ascii_lowercase();

    if k == 'w' {
        if has_horn_uo_pair(buf) || complete_horn_u_plain_o(buf) {
            return Outcome::Transformed;
        }
    }

    if let Some(tone) = tone_key(k) {
        return try_tone(buf, tone, k, caps);
    }

    match k {
        'a' => try_circumflex_or_append(buf, 'a', caps),
        'e' => try_circumflex_or_append(buf, 'e', caps),
        'o' => try_o(buf, caps),
        'w' => try_w(buf, caps),
        'd' => try_stroke_d(buf, caps),
        _ => append_literal_or_complete_horn_uo(buf, k, caps),
    }
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

/// Returns `Transformed` when a Vietnamese transform was applied; `Literal`
/// when the key simply appended (escape candidate on repeat).
fn try_tone(buf: &mut Buffer, tone: Tone, raw_key: char, caps: bool) -> Outcome {
    if buf.is_empty() {
        buf.push(CompChar::new(raw_key, caps));
        return Outcome::Literal;
    }

    let snap = buf.snapshot();
    let cur = tone::current_tone(buf);

    if tone == Tone::None {
        if cur != Tone::None {
            tone::strip_tone(buf);
            if is_valid_syllable(buf) {
                return Outcome::Transformed;
            }
            buf.restore(snap);
        }
        buf.push(CompChar::new(raw_key, caps));
        return Outcome::Literal;
    }

    // Double-key: same tone already present → strip + append raw.
    if cur == tone {
        tone::strip_tone(buf);
        buf.push(CompChar::new(raw_key, caps));
        return Outcome::Literal;
    }

    if !tone::apply_tone(buf, tone) {
        buf.restore(snap);
        buf.push(CompChar::new(raw_key, caps));
        return Outcome::Literal;
    }

    if !is_valid_syllable(buf) {
        buf.restore(snap);
        buf.push(CompChar::new(raw_key, caps));
        return Outcome::Literal;
    }
    Outcome::Transformed
}

/// aa→â, ee→ê, oo→ô; double-key aaa→aa.
fn try_circumflex_or_append(buf: &mut Buffer, letter: char, caps: bool) -> Outcome {
    if let Some(i) = find_rightmost(buf, |c| {
        c.base == letter && (c.mark == Mark::None || c.mark == Mark::Circumflex)
    }) {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Circumflex {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            buf.push(CompChar::new(letter, caps));
            return Outcome::Literal;
        }
        let snap = buf.snapshot();
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Circumflex;
        }
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(snap);
    }
    buf.push(CompChar::new(letter, caps));
    Outcome::Literal
}

fn try_o(buf: &mut Buffer, caps: bool) -> Outcome {
    if buf
        .chars()
        .last()
        .is_some_and(|c| c.base == 'u' && c.mark == Mark::Horn)
    {
        return append_literal_or_complete_horn_uo(buf, 'o', caps);
    }
    try_circumflex_or_append(buf, 'o', caps)
}

fn append_literal_or_complete_horn_uo(buf: &mut Buffer, key: char, caps: bool) -> Outcome {
    buf.push(CompChar::new(key, caps));
    let literal = buf.snapshot();
    if complete_horn_u_plain_o(buf) {
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(literal);
    }
    Outcome::Literal
}

/// Accept the common forgiving order `uwoc` for `ươc`: after `uw` creates `ư`,
/// a later literal `o` becomes the paired `ơ` once the syllable is complete.
fn complete_horn_u_plain_o(buf: &mut Buffer) -> bool {
    let chars = buf.chars().to_vec();
    for i in 0..chars.len().saturating_sub(1) {
        if chars[i].base == 'u'
            && chars[i].mark == Mark::Horn
            && chars[i + 1].base == 'o'
            && chars[i + 1].mark == Mark::None
        {
            if let Some(o) = buf.get_mut(i + 1) {
                o.mark = Mark::Horn;
                return true;
            }
        }
    }
    false
}

fn has_horn_uo_pair(buf: &Buffer) -> bool {
    find_uo_pair(buf).is_some_and(|(i, j)| {
        let chars = buf.chars();
        chars[i].mark == Mark::Horn && chars[j].mark == Mark::Horn
    })
}

/// w: uo+w→ươ, ua+w→ưa, aw→ă, ow→ơ, uw→ư, bare w→ư; double-key reverts.
fn try_w(buf: &mut Buffer, caps: bool) -> Outcome {
    if buf.is_empty() {
        let mut c = CompChar::new('u', caps);
        c.mark = Mark::Horn;
        buf.push(c);
        return Outcome::Transformed;
    }

    let snap = buf.snapshot();

    // Forgiving order: `uwow` should complete the existing `ưo` into `ươ`.
    if has_horn_uo_pair(buf) || complete_horn_u_plain_o(buf) {
        return Outcome::Transformed;
    }

    // Double-key when horn already applied and no further w-action fits.
    if let Some(i) = find_rightmost(buf, |c| c.mark == Mark::Horn) {
        if !can_apply_uo_w(buf) && !can_apply_simple_w(buf) {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            strip_paired_horn(buf);
            buf.push(CompChar::new('w', caps));
            return Outcome::Literal;
        }
    }

    if apply_uo_w(buf) {
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(snap.clone());
    }

    // ua + w → ưa (before aw → ă). Bare `u`+`a` is a nucleus; onset `qu`+`a`
    // is not (`quắm` still uses aw). Without this, aw wins and yields illegal `uă`.
    if apply_ua_w(buf) {
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(snap.clone());
    }

    // aw → ă
    if let Some(i) = find_rightmost(buf, |c| c.base == 'a' && c.mark == Mark::None) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Breve;
        }
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(snap.clone());
    }

    // ow → ơ
    if let Some(i) = find_rightmost(buf, |c| c.base == 'o' && c.mark == Mark::None) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Horn;
        }
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(snap.clone());
    }

    // uw → ư
    if let Some(i) = find_rightmost(buf, |c| c.base == 'u' && c.mark == Mark::None) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Horn;
        }
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(snap.clone());
    }

    if let Some(i) = find_rightmost(buf, |c| c.mark == Mark::Horn) {
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::None;
        }
        strip_paired_horn(buf);
        buf.push(CompChar::new('w', caps));
        return Outcome::Literal;
    }

    let mut c = CompChar::new('u', caps);
    c.mark = Mark::Horn;
    buf.push(c);
    if is_valid_syllable(buf) {
        return Outcome::Transformed;
    }
    buf.restore(snap);
    buf.push(CompChar::new('w', caps));
    Outcome::Literal
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

/// Horn on bare `u` when the buffer has nucleus `ua` (→ `ưa`), not onset `qu`+`a`.
fn apply_ua_w(buf: &mut Buffer) -> bool {
    let Some(a_idx) = find_rightmost(buf, |c| c.base == 'a' && c.mark == Mark::None) else {
        return false;
    };
    if a_idx == 0 {
        return false;
    }
    let u_ok = buf
        .get(a_idx - 1)
        .is_some_and(|c| c.base == 'u' && c.mark == Mark::None);
    if !u_ok {
        return false;
    }
    // `qu` + vowel: `u` belongs to the onset, so `w` must mean `ă` on `a`.
    if a_idx >= 2
        && buf
            .get(a_idx - 2)
            .is_some_and(|q| q.base == 'q' && q.mark == Mark::None)
    {
        return false;
    }
    if let Some(ch) = buf.get_mut(a_idx - 1) {
        ch.mark = Mark::Horn;
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
fn try_stroke_d(buf: &mut Buffer, caps: bool) -> Outcome {
    if let Some(i) = find_rightmost(buf, |c| c.base == 'd') {
        let c = buf.get(i).unwrap();
        if c.mark == Mark::Stroke {
            if let Some(ch) = buf.get_mut(i) {
                ch.mark = Mark::None;
            }
            buf.push(CompChar::new('d', caps));
            return Outcome::Literal;
        }
        let snap = buf.snapshot();
        if let Some(ch) = buf.get_mut(i) {
            ch.mark = Mark::Stroke;
        }
        if is_valid_syllable(buf) {
            return Outcome::Transformed;
        }
        buf.restore(snap);
    }
    buf.push(CompChar::new('d', caps));
    Outcome::Literal
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn complete_horn_u_plain_o_pair() {
        let mut buf = Buffer::new();
        let mut u = CompChar::new('u', false);
        u.mark = Mark::Horn;
        buf.push(u);
        buf.push(CompChar::new('o', false));

        assert!(complete_horn_u_plain_o(&mut buf));
        assert_eq!(buf.display(), "ươ");
    }

    #[test]
    fn process_wow_completes_uo_horn() {
        let mut buf = Buffer::new();
        process(&mut buf, 'w', false);
        assert_eq!(buf.display(), "ư");
        process(&mut buf, 'o', false);
        assert_eq!(buf.display(), "ươ");
        process(&mut buf, 'w', false);
        assert_eq!(buf.display(), "ươ");
    }
}
