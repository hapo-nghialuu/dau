//! Word-scoped composition buffer: base letter + mark + tone + caps.

use crate::engine::tone::{Mark, Tone};

/// One logical character in the composing word.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompChar {
    /// Underlying ASCII base letter (always lowercase a–z).
    pub base: char,
    pub caps: bool,
    pub tone: Tone,
    pub mark: Mark,
}

impl CompChar {
    pub fn new(base: char, caps: bool) -> Self {
        Self {
            base: base.to_ascii_lowercase(),
            caps,
            tone: Tone::None,
            mark: Mark::None,
        }
    }

    pub fn is_vowel(&self) -> bool {
        matches!(self.base, 'a' | 'e' | 'i' | 'o' | 'u' | 'y')
    }

    /// Render to a single Unicode character (Vietnamese letter or plain Latin).
    pub fn to_char(&self) -> char {
        let c = compose_letter(self.base, self.mark, self.tone);
        if self.caps {
            // Unicode uppercase covers Vietnamese precomposed letters.
            c.to_uppercase().next().unwrap_or(c)
        } else {
            c
        }
    }
}

/// Buffer of one composing word.
#[derive(Clone, Debug, Default)]
pub struct Buffer {
    chars: Vec<CompChar>,
}

impl Buffer {
    pub fn new() -> Self {
        Self { chars: Vec::new() }
    }

    pub fn clear(&mut self) {
        self.chars.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.chars.is_empty()
    }

    pub fn chars(&self) -> &[CompChar] {
        &self.chars
    }

    pub fn chars_mut(&mut self) -> &mut [CompChar] {
        &mut self.chars
    }

    pub fn push(&mut self, c: CompChar) {
        self.chars.push(c);
    }

    /// Remove the last logical character (one user-visible display scalar).
    pub fn pop(&mut self) -> Option<CompChar> {
        self.chars.pop()
    }

    pub fn get_mut(&mut self, i: usize) -> Option<&mut CompChar> {
        self.chars.get_mut(i)
    }

    pub fn get(&self, i: usize) -> Option<&CompChar> {
        self.chars.get(i)
    }

    /// Display string of the current word.
    pub fn display(&self) -> String {
        self.chars.iter().map(CompChar::to_char).collect()
    }

    /// Snapshot clone for try/rollback.
    pub fn snapshot(&self) -> Self {
        self.clone()
    }

    pub fn restore(&mut self, other: Self) {
        *self = other;
    }
}

/// Compose base + mark + tone into one Unicode letter.
fn compose_letter(base: char, mark: Mark, tone: Tone) -> char {
    // Index: tone None, Acute, Grave, Hook, Tilde, Dot
    let tone_i = match tone {
        Tone::None => 0,
        Tone::Acute => 1,
        Tone::Grave => 2,
        Tone::Hook => 3,
        Tone::Tilde => 4,
        Tone::Dot => 5,
    };

    match (base, mark) {
        ('a', Mark::None) => ['a', 'á', 'à', 'ả', 'ã', 'ạ'][tone_i],
        ('a', Mark::Circumflex) => ['â', 'ấ', 'ầ', 'ẩ', 'ẫ', 'ậ'][tone_i],
        ('a', Mark::Breve) => ['ă', 'ắ', 'ằ', 'ẳ', 'ẵ', 'ặ'][tone_i],
        ('e', Mark::None) => ['e', 'é', 'è', 'ẻ', 'ẽ', 'ẹ'][tone_i],
        ('e', Mark::Circumflex) => ['ê', 'ế', 'ề', 'ể', 'ễ', 'ệ'][tone_i],
        ('i', Mark::None) => ['i', 'í', 'ì', 'ỉ', 'ĩ', 'ị'][tone_i],
        ('o', Mark::None) => ['o', 'ó', 'ò', 'ỏ', 'õ', 'ọ'][tone_i],
        ('o', Mark::Circumflex) => ['ô', 'ố', 'ồ', 'ổ', 'ỗ', 'ộ'][tone_i],
        ('o', Mark::Horn) => ['ơ', 'ớ', 'ờ', 'ở', 'ỡ', 'ợ'][tone_i],
        ('u', Mark::None) => ['u', 'ú', 'ù', 'ủ', 'ũ', 'ụ'][tone_i],
        ('u', Mark::Horn) => ['ư', 'ứ', 'ừ', 'ử', 'ữ', 'ự'][tone_i],
        ('y', Mark::None) => ['y', 'ý', 'ỳ', 'ỷ', 'ỹ', 'ỵ'][tone_i],
        ('d', Mark::Stroke) => {
            if tone_i == 0 {
                'đ'
            } else {
                // đ does not carry tone; fall back to plain d + tone is invalid
                'đ'
            }
        }
        (b, _) => b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compose_basic() {
        let mut c = CompChar::new('a', false);
        c.tone = Tone::Acute;
        assert_eq!(c.to_char(), 'á');
        c.mark = Mark::Circumflex;
        assert_eq!(c.to_char(), 'ấ');
        c.caps = true;
        assert_eq!(c.to_char(), 'Ấ');
    }
}
