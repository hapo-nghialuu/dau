//! Word-break UX: auto-restore English, ESC restore, shortcuts, auto-capitalize.

use crate::engine::buffer::Buffer;
use crate::engine::syllable::is_valid_committed_syllable;

/// Result of finishing the current word with a break character.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BreakOutput {
    /// Text the engine commits for the finished word (no break char appended).
    pub text: String,
    /// Hint: the next word should capitalize its first letter.
    pub capitalize_next: bool,
}

/// Break characters that may trigger English auto-restore.
///
/// Includes the terminal word breaks the macOS key-classifier already classifies
/// as `breakKey` (space, punctuation, Return, Tab): `\t` (Tab) and `\r`
/// (Return/CR) are added alongside `\n` so composing words ending on Tab or
/// Return restore English the same way they do on space or punctuation. They do
/// **not** set sentence capitalization (conservative policy — see
/// [`is_sentence_end`]).
pub fn is_restore_break(brk: char) -> bool {
    matches!(
        brk,
        ' ' | '.' | ',' | '!' | '?' | '\n' | '\r' | '\t' | ';' | ':'
    )
}

/// Sentence-ending breaks that enable capitalize-next.
///
/// Only true sentence terminators set capitalization. `\t` (Tab) and `\r`
/// (Return/CR) restore English on break but deliberately do not count as
/// sentence ends, keeping the conservative capitalization policy.
pub fn is_sentence_end(brk: char) -> bool {
    matches!(brk, '.' | '!' | '?' | '\n')
}

/// Whether the finished word should commit raw keystrokes instead of composed VN.
///
/// Most English restores are still phonotactic: `text`/`wow` restore because
/// the composed display is not a complete Vietnamese syllable. A few high-
/// confidence daily-English patterns (`case`, `luxury`, `things`, `see`, …)
/// also restore even when the transient display looks Vietnamese-valid. Keep
/// this intentionally pattern-based, not dictionary-based.
pub fn should_auto_restore(
    raw: &str,
    buf: &Buffer,
    auto_restore: bool,
    pass_through: bool,
) -> bool {
    if !auto_restore || pass_through || raw.is_empty() {
        return false;
    }
    if is_high_confidence_english(raw) {
        return true;
    }
    !is_valid_committed_syllable(buf)
}

fn is_high_confidence_english(raw: &str) -> bool {
    let lower = raw.to_ascii_lowercase();
    let word = lower.as_str();

    // Product policy: these short collisions intentionally compose Vietnamese.
    // English variants use explicit repeat/manual escape (`beeen`, `thiss`, …).
    const VIETNAMESE_WINS: &[&str] = &["mix", "box", "six", "this", "been", "as", "is", "us", "or"];
    if VIETNAMESE_WINS.contains(&word) {
        return false;
    }

    // Rare as standalone Vietnamese output, very common in daily English.
    if matches!(word, "of" | "if" | "see" | "luxury" | "expect") {
        return true;
    }

    // `things`/`kings`: English `-ing(s)` + Telex tone marker at the end.
    if word.ends_with("ing") || word.ends_with("ings") {
        return true;
    }

    // `case`/`base`/`use`: final `s` before silent/final `e` is English-like.
    if word.len() >= 3 && word.ends_with("se") {
        return true;
    }

    false
}

/// Longest exact shortcut match for `raw` (case-insensitive key compare).
pub fn match_shortcut<'a>(raw: &str, pairs: &'a [(String, String)]) -> Option<&'a str> {
    let mut best: Option<&(String, String)> = None;
    for pair in pairs {
        if pair.0.eq_ignore_ascii_case(raw)
            && best.as_ref().is_none_or(|b| pair.0.len() > b.0.len())
        {
            best = Some(pair);
        }
    }
    best.map(|(_, v)| v.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::buffer::CompChar;
    use crate::engine::telex;

    fn type_telex(keys: &str) -> (String, Buffer) {
        let mut buf = Buffer::new();
        for ch in keys.chars() {
            telex::process(&mut buf, ch, false);
        }
        (keys.to_string(), buf)
    }

    #[test]
    fn restore_text_via_committed_invalid() {
        let (raw, buf) = type_telex("text");
        assert!(should_auto_restore(&raw, &buf, true, false));
    }

    #[test]
    fn restore_high_confidence_english_even_when_display_valid() {
        for keys in ["case", "luxury", "things", "kings", "of", "if", "see"] {
            let (raw, buf) = type_telex(keys);
            assert!(
                should_auto_restore(&raw, &buf, true, false),
                "{keys} → {} should restore raw English",
                buf.display()
            );
        }
    }

    #[test]
    fn keep_mix_box() {
        for keys in ["mix", "box", "six", "this", "been", "as", "is", "us", "or"] {
            let (raw, buf) = type_telex(keys);
            assert!(
                !should_auto_restore(&raw, &buf, true, false),
                "{keys} → {} should keep Vietnamese",
                buf.display()
            );
        }
    }

    #[test]
    fn restore_wow_open_uo_horn() {
        let (raw, buf) = type_telex("wow");
        assert_eq!(buf.display(), "ươ");
        assert!(should_auto_restore(&raw, &buf, true, false));
    }

    #[test]
    fn keep_vietnamese() {
        let (raw, buf) = type_telex("tieengs");
        assert!(!should_auto_restore(&raw, &buf, true, false));
        assert_eq!(buf.display(), "tiếng");
    }

    #[test]
    fn keep_uo_horn_with_coda() {
        // Multi-w Telex for ươ must NOT restore when the syllable is complete.
        for keys in ["truwowngf", "dduwowngf", "thuwowngr", "nguwowif"] {
            let (raw, buf) = type_telex(keys);
            assert!(
                !should_auto_restore(&raw, &buf, true, false),
                "{keys} → {} should keep VN",
                buf.display()
            );
        }
    }

    #[test]
    fn shortcut_longest_exact() {
        let pairs = vec![
            ("v".into(), "short".into()),
            ("vn".into(), "Việt Nam".into()),
        ];
        assert_eq!(match_shortcut("vn", &pairs), Some("Việt Nam"));
        assert_eq!(match_shortcut("v", &pairs), Some("short"));
        assert_eq!(match_shortcut("vx", &pairs), None);
    }

    #[test]
    fn empty_buffer_not_restore() {
        let buf = Buffer::new();
        assert!(!should_auto_restore("", &buf, true, false));
        let mut buf = Buffer::new();
        buf.push(CompChar::new('a', false));
        assert!(!should_auto_restore("a", &buf, true, false));
    }
}
