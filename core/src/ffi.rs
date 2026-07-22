//! C ABI surface for Fcitx5 (and other) bridges.
//!
//! Opaque `Engine` pointers; string results as UTF-32 code points in [`DauResult`].

use crate::config::{Config, Strategy};
use crate::engine::{Engine, Method};
use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::Path;

/// Maximum UTF-32 code points returned in a single [`DauResult`].
///
/// Kept as a literal `64` in [`DauResult::chars`] so cbindgen emits a valid C array size.
pub const DAU_RESULT_MAX_CHARS: usize = 64;

/// Input method selection for the C ABI.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DauMethod {
    Telex = 0,
    Vni = 1,
}

/// Per-app typing strategy for the C ABI.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DauStrategy {
    Unknown = 0,
    Preedit = 1,
    CommitAtom = 2,
    Passthrough = 3,
}

/// Suggested action for the host IME bridge after a key event.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DauAction {
    None = 0,
    UpdatePreedit = 1,
    Commit = 2,
    Restore = 3,
}

/// Result of one key / break / escape operation.
///
/// C++ reads `chars[0..len]` as UTF-32 code points.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct DauResult {
    pub action: DauAction,
    /// UTF-32 code points (valid prefix length is `len`, max 64).
    pub chars: [u32; 64],
    pub len: u32,
    pub capitalize_next: bool,
}

impl DauResult {
    fn empty() -> Self {
        Self {
            action: DauAction::None,
            chars: [0; 64],
            len: 0,
            capitalize_next: false,
        }
    }

    fn from_text(action: DauAction, text: &str, capitalize_next: bool) -> Self {
        let mut chars = [0u32; 64];
        let mut len = 0u32;
        for (i, ch) in text.chars().take(64).enumerate() {
            chars[i] = ch as u32;
            len = (i + 1) as u32;
        }
        Self {
            action,
            chars,
            len,
            capitalize_next,
        }
    }
}

fn method_from_c(m: DauMethod) -> Method {
    match m {
        DauMethod::Telex => Method::Telex,
        DauMethod::Vni => Method::Vni,
    }
}

/// Create a new engine. Caller must free with [`dau_engine_free`].
#[no_mangle]
pub extern "C" fn dau_engine_new(method: DauMethod) -> *mut Engine {
    let engine = Engine::new(method_from_c(method));
    Box::into_raw(Box::new(engine))
}

/// Free an engine previously returned by [`dau_engine_new`].
///
/// Null is a no-op.
///
/// # Safety
/// - `engine` must be null or a unique pointer previously returned by [`dau_engine_new`].
/// - Must not be used after this call (except null).
#[no_mangle]
pub unsafe extern "C" fn dau_engine_free(engine: *mut Engine) {
    if engine.is_null() {
        return;
    }
    // SAFETY: caller guarantees non-null `engine` came from `Box::into_raw` via `dau_engine_new`.
    drop(Box::from_raw(engine));
}

/// Process one Unicode scalar value (`ch` is UTF-32).
///
/// Returns [`DauAction::UpdatePreedit`] while composing, or [`DauAction::None`]
/// when the engine is disabled / null / invalid code point.
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_process_char(engine: *mut Engine, ch: u32, caps: bool) -> DauResult {
    if engine.is_null() {
        return DauResult::empty();
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    let eng = &mut *engine;
    if !eng.is_enabled() {
        return DauResult::empty();
    }
    let Some(ch) = char::from_u32(ch) else {
        return DauResult::empty();
    };
    let text = eng.process_char(ch, caps);
    DauResult::from_text(DauAction::UpdatePreedit, &text, false)
}

/// End the current word with break character `brk` (UTF-32).
///
/// Returns [`DauAction::Commit`] with committed text (break char not included).
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_on_break(engine: *mut Engine, brk: u32) -> DauResult {
    if engine.is_null() {
        return DauResult::empty();
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    let eng = &mut *engine;
    if !eng.is_enabled() {
        return DauResult::empty();
    }
    let Some(brk) = char::from_u32(brk) else {
        return DauResult::empty();
    };
    let out = eng.on_break(brk);
    DauResult::from_text(DauAction::Commit, &out.text, out.capitalize_next)
}

/// ESC: restore raw keystrokes. Returns [`DauAction::Restore`].
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_escape(engine: *mut Engine) -> DauResult {
    if engine.is_null() {
        return DauResult::empty();
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    let eng = &mut *engine;
    if !eng.is_enabled() {
        return DauResult::empty();
    }
    let raw = eng.escape();
    DauResult::from_text(DauAction::Restore, &raw, false)
}

/// Clear the composing word.
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_clear(engine: *mut Engine) {
    if engine.is_null() {
        return;
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    (*engine).clear();
}

/// Switch input method. Does not clear the current buffer.
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_set_method(engine: *mut Engine, method: DauMethod) {
    if engine.is_null() {
        return;
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    (*engine).set_method(method_from_c(method));
}

/// Enable or disable composition (when disabled, process/break/escape are no-ops).
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_set_enabled(engine: *mut Engine, enabled: bool) {
    if engine.is_null() {
        return;
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    (*engine).set_enabled(enabled);
}

/// Enable/disable auto-capitalize after sentence ends.
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_set_auto_capitalize(engine: *mut Engine, on: bool) {
    if engine.is_null() {
        return;
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    (*engine).set_auto_capitalize(on);
}

/// Enable/disable English auto-restore on word break.
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
#[no_mangle]
pub unsafe extern "C" fn dau_set_auto_restore(engine: *mut Engine, on: bool) {
    if engine.is_null() {
        return;
    }
    // SAFETY: non-null pointer owned by caller, created by `dau_engine_new`.
    (*engine).set_auto_restore(on);
}

/// Load shortcut pairs from a flat C array of UTF-8 C strings.
///
/// `pairs` points to `2 * count` pointers: (key0, value0, key1, value1, ...).
/// Null entries are skipped. Replaces any previous shortcut table.
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
/// - If `pairs` is non-null, it must point to at least `2 * count` readable
///   `*const c_char` entries; each non-null entry must be a valid NUL-terminated
///   UTF-8 C string that remains valid for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn dau_set_shortcuts(
    engine: *mut Engine,
    pairs: *const *const c_char,
    count: usize,
) {
    if engine.is_null() {
        return;
    }
    // SAFETY: non-null engine from `dau_engine_new`.
    let eng = &mut *engine;

    if pairs.is_null() || count == 0 {
        eng.set_shortcuts(Vec::new());
        return;
    }

    let mut table = Vec::with_capacity(count);
    for i in 0..count {
        // SAFETY: caller guarantees `pairs` has at least `2 * count` entries when non-null.
        let key_ptr = *pairs.add(i * 2);
        let val_ptr = *pairs.add(i * 2 + 1);
        if key_ptr.is_null() || val_ptr.is_null() {
            continue;
        }
        // SAFETY: non-null C strings provided by caller; must be valid UTF-8 NUL-terminated.
        let key = match CStr::from_ptr(key_ptr).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => continue,
        };
        let val = match CStr::from_ptr(val_ptr).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => continue,
        };
        table.push((key, val));
    }
    eng.set_shortcuts(table);
}

/// Crate version as a static C string. Do **not** free.
#[no_mangle]
pub extern "C" fn dau_version() -> *const c_char {
    // NUL-terminated compile-time version; static lifetime, never free.
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr().cast::<c_char>()
}

/// Load config from shipped then user TOML paths (UTF-8 C strings; null = skip that file).
///
/// Merges (user overrides shipped), stores on the engine, and applies method / enabled /
/// auto_* / shortcuts when declared. Returns `true` if both parses succeeded (or files
/// were skipped / missing).
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
/// - Non-null path pointers must be valid NUL-terminated UTF-8 C strings for this call.
#[no_mangle]
pub unsafe extern "C" fn dau_load_config(
    engine: *mut Engine,
    shipped_path: *const c_char,
    user_path: *const c_char,
) -> bool {
    if engine.is_null() {
        return false;
    }
    // SAFETY: non-null engine from `dau_engine_new`.
    let eng = &mut *engine;

    let mut base = Config::default();
    if let Some(path) = c_path(shipped_path) {
        match Config::from_file(path) {
            Ok(c) => base = c,
            Err(_) => return false,
        }
    }

    let mut user = Config::default();
    if let Some(path) = c_path(user_path) {
        match Config::from_file(path) {
            Ok(c) => user = c,
            Err(_) => return false,
        }
    }

    eng.apply_config(base.merge(user));
    true
}

/// Look up the typing strategy for `app_id` from the engine's loaded config.
///
/// Returns [`DauStrategy::Unknown`] when the engine is null, `app_id` is null/invalid,
/// or no strategy is configured for that app.
///
/// # Safety
/// - `engine` must be null or a valid live pointer from [`dau_engine_new`].
/// - Non-null `app_id` must be a valid NUL-terminated UTF-8 C string for this call.
#[no_mangle]
pub unsafe extern "C" fn dau_strategy_for_app(
    engine: *mut Engine,
    app_id: *const c_char,
) -> DauStrategy {
    if engine.is_null() || app_id.is_null() {
        return DauStrategy::Unknown;
    }
    // SAFETY: non-null engine from `dau_engine_new`; app_id is a C string for this call.
    let eng = &*engine;
    let Ok(id) = CStr::from_ptr(app_id).to_str() else {
        return DauStrategy::Unknown;
    };
    match eng.config().strategy_for(id) {
        Some(Strategy::Preedit) => DauStrategy::Preedit,
        Some(Strategy::CommitAtom) => DauStrategy::CommitAtom,
        Some(Strategy::Passthrough) => DauStrategy::Passthrough,
        None => DauStrategy::Unknown,
    }
}

/// Convert a non-null C path string to a [`Path`]. Null → `None`. Invalid UTF-8 → `None`.
unsafe fn c_path<'a>(ptr: *const c_char) -> Option<&'a Path> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: caller guarantees valid NUL-terminated C string when non-null.
    let s = CStr::from_ptr(ptr).to_str().ok()?;
    Some(Path::new(s))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::ptr;

    fn utf32_to_string(r: &DauResult) -> String {
        r.chars[..r.len as usize]
            .iter()
            .filter_map(|&c| char::from_u32(c))
            .collect()
    }

    #[test]
    fn round_trip_telex_commit() {
        // SAFETY: engine from dau_engine_new; freed at end of test.
        unsafe {
            let eng = dau_engine_new(DauMethod::Telex);
            assert!(!eng.is_null());
            dau_set_auto_capitalize(eng, false);
            dau_set_auto_restore(eng, false);

            let r = dau_process_char(eng, 'v' as u32, false);
            assert_eq!(r.action, DauAction::UpdatePreedit);
            assert_eq!(utf32_to_string(&r), "v");

            let r = dau_process_char(eng, 'a' as u32, false);
            assert_eq!(utf32_to_string(&r), "va");

            let r = dau_process_char(eng, 'a' as u32, false);
            assert_eq!(utf32_to_string(&r), "vâ");

            let r = dau_process_char(eng, 'n' as u32, false);
            assert_eq!(utf32_to_string(&r), "vân");

            let r = dau_on_break(eng, ' ' as u32);
            assert_eq!(r.action, DauAction::Commit);
            assert_eq!(utf32_to_string(&r), "vân");
            assert!(!r.capitalize_next);

            dau_engine_free(eng);
        }
    }

    #[test]
    fn escape_returns_raw() {
        // SAFETY: engine from dau_engine_new; freed at end of test.
        unsafe {
            let eng = dau_engine_new(DauMethod::Telex);
            dau_set_auto_capitalize(eng, false);

            dau_process_char(eng, 'a' as u32, false);
            dau_process_char(eng, 'a' as u32, false);
            let r = dau_escape(eng);
            assert_eq!(r.action, DauAction::Restore);
            assert_eq!(utf32_to_string(&r), "aa");

            dau_engine_free(eng);
        }
    }

    #[test]
    fn null_safety_no_panic() {
        let null: *mut Engine = ptr::null_mut();
        // SAFETY: null engine is defined as a no-op for all FFI entry points.
        unsafe {
            let r = dau_process_char(null, 'a' as u32, false);
            assert_eq!(r.action, DauAction::None);
            assert_eq!(r.len, 0);

            let r = dau_on_break(null, ' ' as u32);
            assert_eq!(r.action, DauAction::None);

            let r = dau_escape(null);
            assert_eq!(r.action, DauAction::None);

            dau_clear(null);
            dau_set_method(null, DauMethod::Vni);
            dau_set_enabled(null, false);
            dau_set_auto_capitalize(null, false);
            dau_set_auto_restore(null, false);
            dau_set_shortcuts(null, ptr::null(), 0);
            dau_engine_free(null);
        }
    }

    #[test]
    fn set_enabled_disables_composition() {
        // SAFETY: engine from dau_engine_new; freed at end of test.
        unsafe {
            let eng = dau_engine_new(DauMethod::Telex);
            dau_set_auto_capitalize(eng, false);
            dau_set_enabled(eng, false);

            let r = dau_process_char(eng, 'a' as u32, false);
            assert_eq!(r.action, DauAction::None);
            assert_eq!(r.len, 0);

            dau_set_enabled(eng, true);
            let r = dau_process_char(eng, 'a' as u32, false);
            assert_eq!(r.action, DauAction::UpdatePreedit);
            assert_eq!(utf32_to_string(&r), "a");

            dau_engine_free(eng);
        }
    }

    #[test]
    fn set_shortcuts_from_c_strings() {
        // SAFETY: engine from dau_engine_new; CString pointers valid for the call.
        unsafe {
            let eng = dau_engine_new(DauMethod::Telex);
            dau_set_auto_capitalize(eng, false);
            dau_set_auto_restore(eng, false);

            let k = CString::new("vn").unwrap();
            let v = CString::new("Việt Nam").unwrap();
            let ptrs = [k.as_ptr(), v.as_ptr()];
            dau_set_shortcuts(eng, ptrs.as_ptr(), 1);

            for ch in ['v', 'n'] {
                dau_process_char(eng, ch as u32, false);
            }
            let r = dau_on_break(eng, ' ' as u32);
            assert_eq!(r.action, DauAction::Commit);
            assert_eq!(utf32_to_string(&r), "Việt Nam");

            dau_engine_free(eng);
        }
    }

    #[test]
    fn version_is_static_c_string() {
        let p = dau_version();
        assert!(!p.is_null());
        // SAFETY: static C string from dau_version.
        let s = unsafe { CStr::from_ptr(p) }.to_str().unwrap();
        assert!(!s.is_empty());
        assert_eq!(s, env!("CARGO_PKG_VERSION"));
    }

    #[test]
    fn result_truncates_at_64_chars() {
        // SAFETY: engine from dau_engine_new; freed at end of test.
        unsafe {
            let eng = dau_engine_new(DauMethod::Telex);
            dau_set_auto_capitalize(eng, false);
            // 70 letters → display longer than 64; FFI must not overflow.
            for _ in 0..70 {
                let r = dau_process_char(eng, 'a' as u32, false);
                assert!(r.len as usize <= DAU_RESULT_MAX_CHARS);
            }
            let r = dau_on_break(eng, ' ' as u32);
            assert!(r.len as usize <= DAU_RESULT_MAX_CHARS);
            dau_engine_free(eng);
        }
    }

    #[test]
    fn clear_resets_preedit() {
        // SAFETY: engine from dau_engine_new; freed at end of test.
        unsafe {
            let eng = dau_engine_new(DauMethod::Telex);
            dau_set_auto_capitalize(eng, false);
            dau_process_char(eng, 'a' as u32, false);
            dau_clear(eng);
            let r = dau_process_char(eng, 'b' as u32, false);
            assert_eq!(utf32_to_string(&r), "b");
            dau_engine_free(eng);
        }
    }

    #[test]
    fn load_config_applies_method_and_strategy() {
        use std::io::Write;

        let dir = std::env::temp_dir().join(format!("dau_cfg_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let user_path = dir.join("config.toml");
        {
            let mut f = std::fs::File::create(&user_path).unwrap();
            write!(
                f,
                r#"
method = "telex"
enabled = true

[apps]
"org.wezfurlong.wezterm" = "preedit"
"Alacritty" = "commit-atom"
"#
            )
            .unwrap();
        }

        // SAFETY: engine from dau_engine_new; paths are valid CStrings for the call.
        unsafe {
            // Start as VNI so we can observe method change to Telex.
            let eng = dau_engine_new(DauMethod::Vni);
            assert_eq!((*eng).method(), Method::Vni);

            let user_c = CString::new(user_path.to_str().unwrap()).unwrap();
            let ok = dau_load_config(eng, ptr::null(), user_c.as_ptr());
            assert!(ok);
            assert_eq!((*eng).method(), Method::Telex);

            let app = CString::new("org.wezfurlong.wezterm").unwrap();
            assert_eq!(
                dau_strategy_for_app(eng, app.as_ptr()),
                DauStrategy::Preedit
            );
            let app2 = CString::new("Alacritty").unwrap();
            assert_eq!(
                dau_strategy_for_app(eng, app2.as_ptr()),
                DauStrategy::CommitAtom
            );
            let unknown = CString::new("unknown-app").unwrap();
            assert_eq!(
                dau_strategy_for_app(eng, unknown.as_ptr()),
                DauStrategy::Unknown
            );

            // Null-safe.
            assert!(!dau_load_config(ptr::null_mut(), ptr::null(), ptr::null()));
            assert_eq!(
                dau_strategy_for_app(ptr::null_mut(), ptr::null()),
                DauStrategy::Unknown
            );

            dau_engine_free(eng);
        }

        let _ = std::fs::remove_dir_all(&dir);
    }
}
