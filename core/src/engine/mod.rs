//! Vietnamese input engine: Telex / VNI composition pipeline.
//!
//! ## Host display delta (port of Gõ Nhanh contract shape)
//!
//! [`DisplayDelta`] / [`display_delta`] implement the *host-facing* contract of
//! “delete N scalars, then insert these code points” instead of returning the
//! full preedit string. The algorithm is common-prefix based.
//!
//! Portions of this delta contract are derived from **Gõ Nhanh**
//! (`core/src/engine/mod.rs` `Result { chars, action, backspace, count, flags }`):
//!
//! Copyright (c) 2025, Gõ Nhanh Contributors
//! SPDX-License-Identifier: BSD-3-Clause
//! See the root `NOTICE` file for the full license text.
//!
//! Vietnamese Telex/VNI rules in this module and submodules are original Dấu
//! (MIT) work and are **not** ported from Gõ Nhanh.
//!
//! ## Telex repeat-escape (structural, no timing)
//!
//! A repeated Telex trigger key that just transformed the buffer restores the
//! pre-transform snapshot and appends the literal trigger. After escape, the
//! engine keeps composing and remembers a word-level manual-escape flag so a
//! later break commits the composed display, not the raw keystrokes. The flag
//! resets at word boundary; backspace clears both pending and manual state.

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
use telex::Outcome;
pub use ux::BreakOutput;
use ux::{is_restore_break, is_sentence_end, match_shortcut, should_auto_restore};

/// Input method selection.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Method {
    Telex,
    Vni,
}

/// Host-facing display delta: delete `backspace` Unicode scalars, then insert
/// the characters in `insert`.
///
/// Derived from the Gõ Nhanh FFI `Result` contract shape (BSD-3-Clause,
/// Copyright (c) 2025 Gõ Nhanh Contributors). See root `NOTICE`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DisplayDelta {
    /// Number of Unicode scalars (Rust `char`s) the host should delete before inserting.
    pub backspace: u8,
    /// Code points to insert after the backspaces (not the full preedit).
    pub insert: String,
}

impl DisplayDelta {
    /// No host mutation.
    #[inline]
    pub fn none() -> Self {
        Self {
            backspace: 0,
            insert: String::new(),
        }
    }

    /// Whether the host can leave the document unchanged.
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.backspace == 0 && self.insert.is_empty()
    }
}

/// Compute a minimal common-prefix delta from the host-visible `old` display to `new`.
///
/// - `backspace` = number of trailing scalars in `old` after the shared prefix
/// - `insert` = remaining scalars of `new` after the shared prefix
///
/// Both strings are measured in Unicode scalars (`char`), matching IME backspace
/// units used by the macOS/Linux hosts.
///
/// Contract shape derived from Gõ Nhanh (BSD-3-Clause, Copyright (c) 2025
/// Gõ Nhanh Contributors). Implementation is original to Dấu.
pub fn display_delta(old: &str, new: &str) -> DisplayDelta {
    let old_chars: Vec<char> = old.chars().collect();
    let new_chars: Vec<char> = new.chars().collect();
    let mut common = 0usize;
    let limit = old_chars.len().min(new_chars.len());
    while common < limit && old_chars[common] == new_chars[common] {
        common += 1;
    }
    let backspace = (old_chars.len() - common).min(u8::MAX as usize) as u8;
    let insert: String = new_chars[common..].iter().collect();
    DisplayDelta { backspace, insert }
}

/// Pending repeat-escape state: trigger lowercase key + pre-transform Buffer
/// snapshot. When the next Telex key matches the trigger case-insensitively,
/// the engine restores the snapshot and appends the literal trigger.
#[derive(Clone)]
struct Pending {
    /// Lowercase Telex trigger key (`s`/`f`/`r`/`x`/`j`/`z`/`a`/`e`/`o`/`w`/`d`).
    trigger: char,
    /// Buffer snapshot taken before the transform that armed this pending.
    snapshot: Buffer,
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
    /// Pending repeat-escape trigger + snapshot for the current word.
    pending: Option<Pending>,
    /// Word-level manual-escape flag (set whenever a repeat-escape fires).
    manual_escape: bool,
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
            pending: None,
            manual_escape: false,
            config: Config::default(),
        }
    }

    pub fn set_method(&mut self, m: Method) {
        self.method = m;
        // Method change resets the pending trigger (the next Telex key cannot
        // be the same key as one just processed under a different method).
        // The manual-escape flag survives so an in-flight word still commits
        // as composed on break.
        self.pending = None;
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

        // Snapshot BEFORE the transform: a repeat-escape must restore the exact
        // pre-transform buffer (e.g. `aa`→`â` restores to `a`, not `â`).
        let pre_transform = self.buffer.snapshot();
        let outcome = match self.method {
            Method::Telex => telex::process(&mut self.buffer, ch, is_upper),
            Method::Vni => vni::process(&mut self.buffer, ch, is_upper),
        };

        // Telex repeat-escape: if the previous Telex key armed a pending trigger
        // and the new key matches it case-insensitively, restore the pre-transform
        // snapshot and append the literal trigger with the new key's own case.
        let mut escaped = false;
        if self.method == Method::Telex
            && outcome == Outcome::Literal
            && ch.is_ascii_alphabetic()
            && self
                .pending
                .as_ref()
                .is_some_and(|p| p.trigger == ch.to_ascii_lowercase())
        {
            let pending = self.pending.take().expect("checked above");
            self.buffer.restore(pending.snapshot);
            self.buffer.push(CompChar::new(ch, is_upper));
            self.manual_escape = true;
            escaped = true;
        }

        if !escaped {
            // Different key (or non-escape literal): arm a fresh pending only
            // when this key just transformed the buffer, using the snapshot
            // taken before the transform. Literal outcomes arm nothing.
            if self.method == Method::Telex
                && outcome == Outcome::Transformed
                && ch.is_ascii_alphabetic()
            {
                self.pending = Some(Pending {
                    trigger: ch.to_ascii_lowercase(),
                    snapshot: pre_transform,
                });
            } else {
                self.pending = None;
            }
        }

        self.buffer.display()
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
        self.pending = None;
        self.manual_escape = false;
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

    /// Backspace one **user-visible** Unicode scalar while composing.
    ///
    /// # Semantics
    ///
    /// - Removes the last [`CompChar`] from the display buffer (one precomposed
    ///   letter such as `ư`, `ế`, `đ` — not a raw keystroke and not a combining
    ///   mark in isolation).
    /// - Re-syncs [`Self::raw`] so Space / Escape / auto-restore cannot resurrect
    ///   content that was deleted. After an edit, raw is rebuilt from the
    ///   remaining bases (+ caps); marks and tones stay only on the buffer so
    ///   further Telex/VNI keys continue from the edited display state.
    /// - Clears the pending repeat-escape state and the word-level manual-escape
    ///   flag so the user can re-type without inheriting a stale escape context.
    /// - Returns `Some(new_display)` when a scalar was removed (including
    ///   `Some("")` when the last scalar was deleted).
    /// - Returns `None` when there is nothing to delete (empty compose). The
    ///   host should treat that as a no-op and may pass the physical Backspace
    ///   through to the application.
    ///
    /// # Examples (behavior under test)
    ///
    /// - Telex `dduwa` → `đưa`, backspace → `đư`, `a` → `đưa`
    /// - Telex `tieengs` → `tiếng`, backspace → `tiến`, `g` → `tiếng`
    /// - Telex `aa` → `â`, backspace → `""` (one display unit, not raw `a`)
    /// - Empty buffer, backspace → `None`
    pub fn backspace_one_display_scalar(&mut self) -> Option<String> {
        if self.buffer.is_empty() {
            // Defensive: empty display must not keep a zombie raw word.
            if !self.raw_keys.is_empty() {
                self.raw_keys.clear();
                self.pass_through = false;
            }
            self.pending = None;
            self.manual_escape = false;
            return None;
        }

        self.buffer.pop();

        if self.buffer.is_empty() {
            // Full clear of the composing word — same blank state as a fresh word.
            self.raw_keys.clear();
            self.pass_through = false;
            self.pending = None;
            self.manual_escape = false;
            return Some(String::new());
        }

        // Keep raw/buffer consistent for continued typing and commit/restore.
        self.resync_raw_after_display_edit();
        // Edit resets escape state: a fresh display scalar sequence is no
        // longer tied to a prior trigger's snapshot.
        self.pending = None;
        self.manual_escape = false;
        Some(self.buffer.display())
    }

    /// Rebuild `raw_keys` from the remaining buffer after a display-scalar edit.
    ///
    /// Raw is an ASCII-base approximation of what remains (case preserved via
    /// `CompChar::caps`). It is intentionally not a full reverse of Telex/VNI
    /// key history: the buffer owns marks/tones for further composition, while
    /// raw only needs to be short enough that deleted tails cannot reappear on
    /// Space auto-restore or Escape.
    fn resync_raw_after_display_edit(&mut self) {
        self.raw_keys = raw_keys_from_buffer(&self.buffer);
    }

    fn commit_current_word(&self, brk: char) -> String {
        if self.raw_keys.is_empty() && self.buffer.is_empty() {
            return String::new();
        }
        let display = self.buffer.display();

        // 1) Shortcuts win (exact match on raw, longest key). They apply even
        // when the manual-escape flag is set — the user explicitly mapped the
        // raw keystrokes.
        if let Some(exp) = match_shortcut(&self.raw_keys, &self.shortcuts) {
            return exp.to_string();
        }

        // 2) Manual-escape flag: the user explicitly typed a repeat-escape
        // during this word, so commit the composed display, not the raw
        // keystrokes. This path is driven entirely by an in-band repeat
        // trigger, not a word list.
        if self.manual_escape {
            return display;
        }

        // 3) Phonotactic fallback (existing behavior, unchanged).
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

        // 4) After ESC pass-through, commit raw (buffer already mirrors raw).
        if self.pass_through {
            return self.raw_keys.clone();
        }

        // 5) Keep composed Vietnamese (or plain display).
        display
    }

    fn reset_word_state(&mut self) {
        self.buffer.clear();
        self.raw_keys.clear();
        self.pass_through = false;
        self.pending = None;
        self.manual_escape = false;
    }
}

/// ASCII-base raw string derived from remaining [`CompChar`]s (caps preserved).
fn raw_keys_from_buffer(buf: &Buffer) -> String {
    let mut raw = String::with_capacity(buf.chars().len());
    for c in buf.chars() {
        let ch = if c.caps {
            c.base.to_ascii_uppercase()
        } else {
            c.base
        };
        raw.push(ch);
    }
    raw
}

#[cfg(test)]
mod evidence_tests;
#[cfg(test)]
#[path = "manual-revert-tests.rs"]
mod manual_revert_tests;
#[cfg(test)]
mod ux_tests;
