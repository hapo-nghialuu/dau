//! Shared buffer helpers for Telex / VNI transforms.

use crate::engine::buffer::{Buffer, CompChar};

/// Rightmost index matching `pred`, if any.
pub fn find_rightmost(buf: &Buffer, pred: impl Fn(&CompChar) -> bool) -> Option<usize> {
    buf.chars()
        .iter()
        .enumerate()
        .rev()
        .find(|(_, c)| pred(c))
        .map(|(i, _)| i)
}

/// Rightmost adjacent plain `uo` pair (bases u then o).
pub fn find_uo_pair(buf: &Buffer) -> Option<(usize, usize)> {
    let chars = buf.chars();
    for i in (0..chars.len()).rev() {
        if chars[i].base == 'u' {
            if let Some(c2) = chars.get(i + 1) {
                if c2.base == 'o' {
                    return Some((i, i + 1));
                }
            }
        }
    }
    None
}
