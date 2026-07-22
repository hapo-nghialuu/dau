//! Tone and mark types, plus modern-style tone placement.

use crate::engine::buffer::Buffer;

/// Vietnamese tone (thanh).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Tone {
    #[default]
    None,
    /// sắc
    Acute,
    /// huyền
    Grave,
    /// hỏi
    Hook,
    /// ngã
    Tilde,
    /// nặng
    Dot,
}

/// Vowel / consonant diacritic mark (dấu phụ).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Mark {
    #[default]
    None,
    /// â ê ô
    Circumflex,
    /// ơ ư
    Horn,
    /// ă
    Breve,
    /// đ
    Stroke,
}

/// Clear all tones from the buffer (keep marks).
pub fn clear_all_tones(buf: &mut Buffer) {
    for c in buf.chars_mut() {
        c.tone = Tone::None;
    }
}

/// Apply `tone` to the correct vowel using modern placement rules.
/// Returns `true` if a vowel was found and tone was written.
pub fn apply_tone(buf: &mut Buffer, tone: Tone) -> bool {
    let Some(idx) = find_tone_target(buf) else {
        return false;
    };
    // Clear tones elsewhere so only one tone exists on the syllable.
    clear_all_tones(buf);
    if let Some(c) = buf.get_mut(idx) {
        c.tone = tone;
        true
    } else {
        false
    }
}

/// Index of the vowel that should carry the tone (kiểu mới).
///
/// Rules (priority order):
/// 1. Vowel with mark (â/ă/ê/ô/ơ/ư) always preferred.
/// 2. Else if syllable has a final consonant → last vowel of the nucleus
///    (e.g. toán, hoá with coda: tone on a/e/y of oa/oe/uy).
/// 3. Else open syllable:
///    - 3 vowels → middle
///    - 2 vowels ∈ {oa, oe, uy} → second; otherwise → first
///    - 1 vowel → itself
pub fn find_tone_target(buf: &Buffer) -> Option<usize> {
    let chars = buf.chars();
    if chars.is_empty() {
        return None;
    }

    // Collect vowel indices (base letters that are vowels; đ is not a vowel).
    let vowels: Vec<usize> = chars
        .iter()
        .enumerate()
        .filter(|(_, c)| c.is_vowel())
        .map(|(i, _)| i)
        .collect();

    if vowels.is_empty() {
        return None;
    }

    // 1. Prefer marked vowels (â ă ê ô ơ ư).
    let marked: Vec<usize> = vowels
        .iter()
        .copied()
        .filter(|&i| {
            let c = &chars[i];
            matches!(c.mark, Mark::Circumflex | Mark::Horn | Mark::Breve)
        })
        .collect();

    if marked.len() == 1 {
        return Some(marked[0]);
    }
    if marked.len() > 1 {
        // e.g. ươ: prefer ơ (last marked), the main vowel.
        return Some(marked[marked.len() - 1]);
    }

    // No marks: structural rules.
    let vcount = vowels.len();
    let last_vowel_i = vowels[vcount - 1];
    let has_final = last_vowel_i + 1 < chars.len();

    // 2. Closed syllable → tone on last vowel of the nucleus.
    if has_final {
        return Some(last_vowel_i);
    }

    // 3. Open syllable.
    match vcount {
        1 => Some(vowels[0]),
        2 => {
            let pair = (chars[vowels[0]].base, chars[vowels[1]].base);
            if matches!(pair, ('o', 'a') | ('o', 'e') | ('u', 'y')) {
                Some(vowels[1])
            } else {
                // Other open diphthongs (ai, ao, eo, …) → first vowel.
                Some(vowels[0])
            }
        }
        3 => Some(vowels[1]), // e.g. oai → a
        _ => Some(vowels[vcount - 2]),
    }
}

/// Whether the buffer currently has any non-None tone.
pub fn current_tone(buf: &Buffer) -> Tone {
    buf.chars()
        .iter()
        .find(|c| c.tone != Tone::None)
        .map(|c| c.tone)
        .unwrap_or(Tone::None)
}

/// Strip tone from target (for double-key revert of tone keys).
pub fn strip_tone(buf: &mut Buffer) -> bool {
    let had = current_tone(buf) != Tone::None;
    clear_all_tones(buf);
    had
}
