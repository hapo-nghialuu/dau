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
pub fn is_restore_break(brk: char) -> bool {
    matches!(brk, ' ' | '.' | ',' | '!' | '?' | '\n' | ';' | ':')
}

/// Sentence-ending breaks that enable capitalize-next.
pub fn is_sentence_end(brk: char) -> bool {
    matches!(brk, '.' | '!' | '?' | '\n')
}

/// Whether the finished word should commit raw keystrokes instead of composed VN.
///
/// Principle: restore **only** when the composed form is not a valid committed
/// Vietnamese syllable. Valid results (including multi-`w` Telex like
/// `truwowngf`→`trường`) are always kept. English like `text`/`wow` restores
/// because they fail commit-time phonotactics, not because of raw key counts.
pub fn should_auto_restore(
    raw: &str,
    buf: &Buffer,
    auto_restore: bool,
    pass_through: bool,
) -> bool {
    if !auto_restore || pass_through || raw.is_empty() {
        return false;
    }
    !is_valid_committed_syllable(buf)
}

/// Keep explicitly supported Telex undo sequences after English auto-restore.
///
/// The raw keystrokes alone cannot distinguish deliberate undo (`tesst` →
/// `test`) from genuine doubled English letters (`coffee`, `errs`, `cliffs`).
/// Keep this list conservative until a real English lexicon is available.
pub fn should_keep_explicit_telex_revert(raw: &str, display: &str) -> bool {
    const REVERTS: &[(&str, &str)] = &[("tesst", "test")];

    REVERTS.iter().any(|(typed, shown)| {
        raw.eq_ignore_ascii_case(typed) && display.eq_ignore_ascii_case(shown)
    })
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
    fn keep_mix_box() {
        let (raw, buf) = type_telex("mix");
        assert!(!should_auto_restore(&raw, &buf, true, false));
        let (raw, buf) = type_telex("box");
        assert!(!should_auto_restore(&raw, &buf, true, false));
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
