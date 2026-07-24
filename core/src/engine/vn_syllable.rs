//! Syllable split (onset / nucleus / coda) and 5 validation laws.

use crate::engine::buffer::{Buffer, CompChar};
use crate::engine::tone::{Mark, Tone};

/// Valid single-letter onsets.
const SINGLE_ONSETS: &[&str] = &[
    "b", "c", "d", "g", "h", "k", "l", "m", "n", "p", "q", "r", "s", "t", "v", "x",
];

/// Valid multi-letter onsets (longest first for matching).
const MULTI_ONSETS: &[&str] = &[
    "ngh", "ng", "gh", "gi", "kh", "ch", "nh", "ph", "th", "tr", "qu",
];

/// Valid codas (final consonants).
const CODAS: &[&str] = &["ng", "nh", "ch", "c", "m", "n", "p", "t"];

/// Result of splitting a word buffer into syllable parts (indices into buffer).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyllableParts {
    pub onset: (usize, usize),
    pub nucleus: (usize, usize),
    pub coda: (usize, usize),
}

/// Validate the whole buffer as one Vietnamese syllable (5 laws).
///
/// Partial onset-only input (e.g. `đ`) is allowed so marks like `dd→đ` work.
/// Used during composition (try/rollback); more permissive than commit-time checks.
pub fn is_valid_syllable(buf: &Buffer) -> bool {
    if buf.is_empty() {
        return true;
    }
    if !buf.chars().iter().any(|c| c.is_vowel()) {
        return is_valid_onset_prefix(buf);
    }
    validate_laws(buf).is_ok()
}

/// Commit-time syllable check: base 5 laws plus phonotactic commit constraints.
///
/// Extra rules (composition still uses the looser [`is_valid_syllable`]):
/// - Finals `p/t/c/ch` only allow no-tone, sắc, or nặng — not huyền/hỏi/ngã
///   (catches English like `text`→`tẽt` while keeping open `mix`→`mĩ`).
/// - Open nucleus `ươ` (no coda) is not a complete written syllable — rejects
///   bare `wow`→`ươ` while keeping `trường`/`đường`/… with coda or glide.
pub fn is_valid_committed_syllable(buf: &Buffer) -> bool {
    if !is_valid_syllable(buf) {
        return false;
    }
    if buf.is_empty() {
        return true;
    }
    let chars = buf.chars();
    let Some(parts) = split_syllable(chars) else {
        return false;
    };
    let coda: String = chars[parts.coda.0..parts.coda.1]
        .iter()
        .map(|c| c.base)
        .collect();
    if matches!(coda.as_str(), "p" | "t" | "c" | "ch") {
        for c in chars {
            if matches!(c.tone, Tone::Grave | Tone::Hook | Tone::Tilde) {
                return false;
            }
        }
    }
    // ươ must take a coda (or glide coda i/u/y) in real Vietnamese orthography.
    if coda.is_empty() && is_uo_horn_nucleus(chars, parts.nucleus) {
        return false;
    }
    true
}

/// Nucleus is exactly the horn pair `ươ` (bases u+o, both Horn).
fn is_uo_horn_nucleus(chars: &[CompChar], nucleus: (usize, usize)) -> bool {
    if nucleus.1 - nucleus.0 != 2 {
        return false;
    }
    let u = &chars[nucleus.0];
    let o = &chars[nucleus.0 + 1];
    u.base == 'u' && u.mark == Mark::Horn && o.base == 'o' && o.mark == Mark::Horn
}

fn is_valid_onset_prefix(buf: &Buffer) -> bool {
    let bases: String = buf.chars().iter().map(|c| c.base).collect();
    if bases.is_empty() {
        return true;
    }
    if is_valid_onset(&bases) {
        return true;
    }
    const PREFIXES: &[&str] = &[
        "n", "ng", "g", "c", "k", "t", "p", "q", "s", "d", "b", "h", "l", "m", "r", "v", "x",
    ];
    if PREFIXES.contains(&bases.as_str()) {
        for c in buf.chars() {
            if c.mark != Mark::None && !(c.base == 'd' && c.mark == Mark::Stroke) {
                return false;
            }
            if !c.base.is_ascii_alphabetic() {
                return false;
            }
        }
        return true;
    }
    false
}

fn validate_laws(buf: &Buffer) -> Result<(), &'static str> {
    let chars = buf.chars();

    for c in chars {
        if !c.base.is_ascii_alphabetic() {
            return Err("law3: non-alphabetic base");
        }
        if !mark_compatible(c) {
            return Err("law3: incompatible mark");
        }
    }

    let bases: String = chars.iter().map(|c| c.base).collect();
    let Some(parts) = split_syllable(chars) else {
        return Err("cannot split syllable");
    };

    if parts.nucleus.0 == parts.nucleus.1 {
        return Err("law1: no vowel");
    }

    let onset = &bases[parts.onset.0..parts.onset.1];
    if !onset.is_empty() && !is_valid_onset(onset) {
        return Err("law2: invalid onset");
    }

    let coda = &bases[parts.coda.0..parts.coda.1];
    if !coda.is_empty() && !is_valid_coda(coda) && !is_semivowel_coda(coda) {
        return Err("law5: invalid coda");
    }

    let nucleus_first = chars
        .get(parts.nucleus.0)
        .map(effective_vowel_class)
        .unwrap_or('a');
    if !onset_vowel_harmony(onset, nucleus_first) {
        return Err("law4: c/k/g/gh/ng/ngh harmony");
    }

    for c in chars.iter().take(parts.nucleus.1).skip(parts.nucleus.0) {
        if !c.is_vowel() {
            return Err("law3: non-vowel in nucleus");
        }
    }

    // Illegal nucleus `uă` (plain u + breve a). Real orthography uses `ưa`.
    // Onset `qu` + `ă` (e.g. quắm) is fine: nucleus is only `ă`.
    if is_ua_breve_nucleus(chars, parts.nucleus) {
        return Err("illegal nucleus uă");
    }

    Ok(())
}

/// Nucleus is exactly plain `u` + `ă` (breve on a) — not a Vietnamese nucleus.
fn is_ua_breve_nucleus(chars: &[CompChar], nucleus: (usize, usize)) -> bool {
    if nucleus.1 - nucleus.0 != 2 {
        return false;
    }
    let u = &chars[nucleus.0];
    let a = &chars[nucleus.0 + 1];
    u.base == 'u'
        && u.mark == Mark::None
        && a.base == 'a'
        && a.mark == Mark::Breve
}

fn mark_compatible(c: &CompChar) -> bool {
    match c.mark {
        Mark::None => true,
        Mark::Circumflex => matches!(c.base, 'a' | 'e' | 'o'),
        Mark::Horn => matches!(c.base, 'o' | 'u'),
        Mark::Breve => c.base == 'a',
        Mark::Stroke => c.base == 'd',
    }
}

fn is_front_vowel_class(v: char) -> bool {
    matches!(v, 'e' | 'i' | 'y')
}

fn effective_vowel_class(c: &CompChar) -> char {
    match c.base {
        'a' | 'e' | 'i' | 'o' | 'u' | 'y' => c.base,
        b => b,
    }
}

fn onset_vowel_harmony(onset: &str, first_vowel: char) -> bool {
    let front = is_front_vowel_class(first_vowel);
    match onset {
        "k" | "gh" | "ngh" => front,
        "c" | "g" | "ng" => !front,
        _ => true,
    }
}

fn is_valid_onset(onset: &str) -> bool {
    MULTI_ONSETS.contains(&onset) || SINGLE_ONSETS.contains(&onset)
}

fn is_valid_coda(coda: &str) -> bool {
    CODAS.contains(&coda)
}

fn is_semivowel_coda(coda: &str) -> bool {
    matches!(coda, "i" | "o" | "u" | "y")
}

fn is_vowel_char(c: char) -> bool {
    matches!(c, 'a' | 'e' | 'i' | 'o' | 'u' | 'y')
}

/// Split buffer chars into onset / nucleus / coda by indices.
pub fn split_syllable(chars: &[CompChar]) -> Option<SyllableParts> {
    if chars.is_empty() {
        return Some(SyllableParts {
            onset: (0, 0),
            nucleus: (0, 0),
            coda: (0, 0),
        });
    }

    let bases: String = chars.iter().map(|c| c.base).collect();
    let n = chars.len();
    let mut onset_end = detect_onset(&bases, n);

    if bases.starts_with("gi") && n > 2 && is_vowel_char(bases.as_bytes()[2] as char) {
        onset_end = 2;
    } else if bases.starts_with("gi") && n == 2 {
        onset_end = 1;
    }

    if bases.starts_with("qu") && (n == 2 || (n > 2 && is_vowel_char(bases.as_bytes()[2] as char)))
    {
        onset_end = 2;
    }

    let mut nuc_start = onset_end;
    let mut nuc_end = onset_end;
    while nuc_end < n && chars[nuc_end].is_vowel() {
        nuc_end += 1;
    }

    if nuc_start == nuc_end {
        if let Some(vi) = chars.iter().position(|c| c.is_vowel()) {
            nuc_start = vi;
            nuc_end = vi;
            while nuc_end < n && chars[nuc_end].is_vowel() {
                nuc_end += 1;
            }
            let on = &bases[..nuc_start];
            if !on.is_empty() && !is_valid_onset(on) {
                return None;
            }
            onset_end = nuc_start;
        } else {
            return Some(SyllableParts {
                onset: (0, n),
                nucleus: (n, n),
                coda: (n, n),
            });
        }
    }

    let coda_start = nuc_end;
    let coda_end = n;
    if chars
        .iter()
        .take(coda_end)
        .skip(coda_start)
        .any(|c| c.is_vowel())
    {
        return None;
    }

    Some(SyllableParts {
        onset: (0, onset_end),
        nucleus: (nuc_start, nuc_end),
        coda: (coda_start, coda_end),
    })
}

fn detect_onset(bases: &str, n: usize) -> usize {
    let mut onset_end = 0usize;
    for len in (1..=3).rev() {
        if len > n {
            continue;
        }
        let cand = &bases[..len];
        if is_valid_onset(cand) {
            if cand == "gi" || cand == "qu" {
                onset_end = len;
                break;
            }
            if cand.chars().all(|ch| !is_vowel_char(ch)) {
                onset_end = len;
                break;
            }
        }
    }
    if onset_end == 0 && n > 0 {
        let c0 = bases.chars().next().unwrap();
        if !is_vowel_char(c0) && SINGLE_ONSETS.contains(&bases[..1].as_ref()) {
            onset_end = 1;
        }
        for len in (2..=3).rev() {
            if len <= n {
                let cand = &bases[..len];
                if MULTI_ONSETS.contains(&cand)
                    && cand != "gi"
                    && cand != "qu"
                    && cand.chars().all(|ch| !is_vowel_char(ch))
                {
                    onset_end = len;
                    break;
                }
            }
        }
    }
    onset_end
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::buffer::CompChar;

    fn buf_from(s: &str) -> Buffer {
        let mut b = Buffer::new();
        for ch in s.chars() {
            b.push(CompChar::new(ch, false));
        }
        b
    }

    #[test]
    fn valid_simple() {
        assert!(is_valid_syllable(&buf_from("viet")));
        assert!(is_valid_syllable(&buf_from("tieng")));
        assert!(is_valid_syllable(&buf_from("hoa")));
        assert!(is_valid_syllable(&buf_from("nguoi")));
    }

    #[test]
    fn invalid_onset_z() {
        assert!(!is_valid_syllable(&buf_from("zzs")));
    }

    #[test]
    fn invalid_no_vowel() {
        assert!(!is_valid_syllable(&buf_from("btw")));
    }

    fn push_marked(b: &mut Buffer, base: char, mark: Mark) {
        let mut c = CompChar::new(base, false);
        c.mark = mark;
        b.push(c);
    }

    #[test]
    fn rejects_illegal_nucleus_ua_breve() {
        // đuă — onset đ, nucleus uă
        let mut b = Buffer::new();
        push_marked(&mut b, 'd', Mark::Stroke);
        b.push(CompChar::new('u', false));
        push_marked(&mut b, 'a', Mark::Breve);
        assert!(!is_valid_syllable(&b));
        assert!(!is_valid_committed_syllable(&b));
        assert_eq!(b.display(), "đuă");
    }

    #[test]
    fn keeps_legal_ua_ua_horn_and_qu_breve() {
        // đua
        let mut dua = Buffer::new();
        push_marked(&mut dua, 'd', Mark::Stroke);
        dua.push(CompChar::new('u', false));
        dua.push(CompChar::new('a', false));
        assert!(is_valid_syllable(&dua));
        assert!(is_valid_committed_syllable(&dua));

        // đưa
        let mut dua_horn = Buffer::new();
        push_marked(&mut dua_horn, 'd', Mark::Stroke);
        push_marked(&mut dua_horn, 'u', Mark::Horn);
        dua_horn.push(CompChar::new('a', false));
        assert!(is_valid_syllable(&dua_horn));
        assert!(is_valid_committed_syllable(&dua_horn));
        assert_eq!(dua_horn.display(), "đưa");

        // đầu — nucleus âu
        let mut dau = Buffer::new();
        push_marked(&mut dau, 'd', Mark::Stroke);
        push_marked(&mut dau, 'a', Mark::Circumflex);
        dau.push(CompChar::new('u', false));
        // tone grave on â for đầu
        if let Some(ch) = dau.get_mut(1) {
            ch.tone = Tone::Grave;
        }
        assert!(is_valid_syllable(&dau));
        assert!(is_valid_committed_syllable(&dau));
        assert_eq!(dau.display(), "đầu");

        // quắm — onset qu, nucleus ă + coda m
        let mut quam = Buffer::new();
        quam.push(CompChar::new('q', false));
        quam.push(CompChar::new('u', false));
        push_marked(&mut quam, 'a', Mark::Breve);
        quam.push(CompChar::new('m', false));
        if let Some(ch) = quam.get_mut(2) {
            ch.tone = Tone::Acute;
        }
        assert!(is_valid_syllable(&quam));
        assert!(is_valid_committed_syllable(&quam));
        assert_eq!(quam.display(), "quắm");
    }
}
