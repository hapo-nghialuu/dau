//! `dau-core` — Vietnamese input method core engine (Telex / VNI).

pub mod config;
mod engine;
pub mod ffi;

pub use config::{Config, Strategy};
pub use engine::{display_delta, BreakOutput, DisplayDelta, Engine, Method};

/// Returns the crate version from Cargo.toml.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_not_empty() {
        assert!(!version().is_empty());
    }
}
