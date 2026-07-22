//! Vietnamese input engine: Telex / VNI composition pipeline.

mod buffer;
// Explicit path avoids ambiguity when leftover `syllable.rs` / `syllable/` coexist.
#[path = "vn_syllable.rs"]
mod syllable;
mod telex;
mod tone;
mod util;
mod ux;
mod vni;

use crate::config::Config;
use buffer::{Buffer, CompChar};
use ux::{is_restore_break, is_sentence_end, match_shortcut, should_auto_restore};

pub use ux::BreakOutput;

/// Input method selection.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Method {
    Telex,
    Vni,
}

/// Core composing engine for one word at a time.
pub struct Engine {
    method: Method,
    buffer: Buffer,
    /// Raw keystrokes for the current word (pre-Vietnamese transform).
    raw_keys: String,
    /// After ESC: append literally, do not re-apply Telex/VNI on the word.
    pass_through: bool,
    /// First letter of the next word should be uppercase.
    capitalize_next: bool,
    auto_capitalize: bool,
    auto_restore: bool,
    /// When false, IME is off (FFI layer skips composition).
    enabled: bool,
    shortcuts: Vec<(String, String)>,
    /// Loaded config (shipped + user merge). Used for strategy lookup via FFI.
    config: Config,
}

impl Engine {
    pub fn new(method: Method) -> Self {
        Self {
            method,
            buffer: Buffer::new(),
            raw_keys: String::new(),
            pass_through: false,
            // Start of stream → capitalize first word.
            capitalize_next: true,
            auto_capitalize: true,
            auto_restore: true,
            enabled: true,
            shortcuts: Vec::new(),
            config: Config::default(),
        }
    }

    pub fn set_method(&mut self, m: Method) {
        self.method = m;
        // Keep buffer; method only affects future keys.
    }

    /// Current input method.
    pub fn method(&self) -> Method {
        self.method
    }

    /// Loaded configuration (after [`Self::apply_config`] / FFI load).
    pub fn config(&self) -> &Config {
        &self.config
    }

    /// Store merged config and apply declared settings (method / enabled / auto_* / shortcuts).
    pub fn apply_config(&mut self, cfg: Config) {
        if let Some(m) = cfg.method {
            self.set_method(m);
        }
        if let Some(on) = cfg.enabled {
            self.set_enabled(on);
        }
        if let Some(on) = cfg.auto_capitalize {
            self.set_auto_capitalize(on);
        }
        if let Some(on) = cfg.auto_restore {
            self.set_auto_restore(on);
        }
        if !cfg.shortcuts.is_empty() {
            self.set_shortcuts(cfg.shortcuts.clone());
        }
        self.config = cfg;
    }

    /// Enable/disable the IME (used by the C FFI bridge).
    pub fn set_enabled(&mut self, on: bool) {
        self.enabled = on;
    }

    /// Whether the IME is currently enabled.
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Load shortcut table (key → expansion). Replaces any previous table.
    pub fn set_shortcuts(&mut self, pairs: Vec<(String, String)>) {
        self.shortcuts = pairs;
    }

    /// Raw keystrokes typed for the current word (before Vietnamese transforms).
    pub fn raw(&self) -> String {
        self.raw_keys.clone()
    }

    /// Enable/disable auto-capitalize of the first letter after sentence ends.
    pub fn set_auto_capitalize(&mut self, on: bool) {
        self.auto_capitalize = on;
    }

    /// Enable/disable English auto-restore on word break.
    pub fn set_auto_restore(&mut self, on: bool) {
        self.auto_restore = on;
    }

    /// Process one key. `caps` forces uppercase when the OS reports Caps/Shift.
    /// Returns the current display string of the composing word.
    pub fn process_char(&mut self, ch: char, caps: bool) -> String {
        let mut is_upper = caps || ch.is_ascii_uppercase();

        // Auto-capitalize: first alphabetic key of a new word.
        if self.auto_capitalize
            && self.capitalize_next
            && self.buffer.is_empty()
            && ch.is_ascii_alphabetic()
        {
            is_upper = true;
            self.capitalize_next = false;
        }

        // Track raw keystroke (case as applied to the letter).
        let raw_ch = if ch.is_ascii_alphabetic() {
            if is_upper {
                ch.to_ascii_uppercase()
            } else {
                ch.to_ascii_lowercase()
            }
        } else {
            ch
        };
        self.raw_keys.push(raw_ch);

        if self.pass_through {
            self.buffer.push(CompChar::new(ch, is_upper));
            return self.buffer.display();
        }

        match self.method {
            Method::Telex => telex::process(&mut self.buffer, ch, is_upper),
            Method::Vni => vni::process(&mut self.buffer, ch, is_upper),
        }
    }

    /// ESC: cancel transforms, return raw keystrokes; buffer enters restored state.
    pub fn escape(&mut self) -> String {
        let raw = self.raw_keys.clone();
        self.buffer.clear();
        for ch in raw.chars() {
            let upper = ch.is_ascii_uppercase();
            self.buffer.push(CompChar::new(ch, upper));
        }
        self.pass_through = true;
        raw
    }

    /// Finish the current word with break character `brk`.
    /// Does not append `brk` to the committed text.
    pub fn on_break(&mut self, brk: char) -> BreakOutput {
        let had_word = !self.raw_keys.is_empty() || !self.buffer.is_empty();
        let text = self.commit_current_word(brk);

        if is_sentence_end(brk) {
            self.capitalize_next = true;
        } else if had_word {
            // Mid-sentence word finished → do not capitalize the next word.
            // Empty break (e.g. space after `.`) keeps the existing flag.
            self.capitalize_next = false;
        }

        self.reset_word_state();

        BreakOutput {
            text,
            capitalize_next: self.capitalize_next,
        }
    }

    /// Reset the composing word (call on space / enter / break).
    pub fn clear(&mut self) {
        self.reset_word_state();
    }

    /// Current composing word display string.
    pub fn composing(&self) -> String {
        self.buffer.display()
    }

    fn commit_current_word(&self, brk: char) -> String {
        if self.raw_keys.is_empty() && self.buffer.is_empty() {
            return String::new();
        }

        // 1) Shortcuts (before auto-restore), exact match on raw, longest key.
        if let Some(exp) = match_shortcut(&self.raw_keys, &self.shortcuts) {
            return exp.to_string();
        }

        // 2) Auto-restore English on word-break characters.
        if is_restore_break(brk)
            && should_auto_restore(
                &self.raw_keys,
                &self.buffer,
                self.auto_restore,
                self.pass_through,
            )
        {
            return self.raw_keys.clone();
        }

        // 3) After ESC pass-through, commit raw (buffer already mirrors raw).
        if self.pass_through {
            return self.raw_keys.clone();
        }

        // 4) Keep composed Vietnamese (or plain display).
        self.buffer.display()
    }

    fn reset_word_state(&mut self) {
        self.buffer.clear();
        self.raw_keys.clear();
        self.pass_through = false;
    }
}

#[cfg(test)]
mod evidence_tests;
#[cfg(test)]
mod ux_tests;
