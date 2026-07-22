//! WASM demo wrapper cho `dau-core`.
//! Export hàm C-ABI đơn giản (buffer tĩnh, trả độ dài) để glue JS thuần đọc,
//! tránh sret struct lớn và không cần allocator. Chỉ dùng cho demo trình duyệt.
#![allow(static_mut_refs)]

use dau_core::{Engine, Method};

static mut ENGINE: Option<Engine> = None;
static mut BUF: [u8; 1024] = [0; 1024];

fn engine() -> &'static mut Engine {
    unsafe {
        if ENGINE.is_none() {
            ENGINE = Some(Engine::new(Method::Telex));
        }
        ENGINE.as_mut().unwrap()
    }
}

/// Copy chuỗi UTF-8 vào buffer tĩnh, trả số byte (để JS đọc BUF[0..len]).
fn write_buf(s: &str) -> u32 {
    let b = s.as_bytes();
    let n = b.len().min(1024);
    unsafe {
        BUF[..n].copy_from_slice(&b[..n]);
    }
    n as u32
}

#[no_mangle]
pub extern "C" fn demo_reset() {
    engine().clear();
}

/// vni != 0 → VNI, ngược lại Telex.
#[no_mangle]
pub extern "C" fn demo_set_method(vni: u32) {
    engine().set_method(if vni != 0 { Method::Vni } else { Method::Telex });
}

#[no_mangle]
pub extern "C" fn demo_set_auto_cap(on: u32) {
    engine().set_auto_capitalize(on != 0);
}

#[no_mangle]
pub extern "C" fn demo_set_auto_restore(on: u32) {
    engine().set_auto_restore(on != 0);
}

/// Xử lý 1 ký tự (UTF-32). Trả độ dài chuỗi đang soạn trong BUF.
#[no_mangle]
pub extern "C" fn demo_process(ch: u32) -> u32 {
    match char::from_u32(ch) {
        Some(c) => {
            let s = engine().process_char(c, false);
            write_buf(&s)
        }
        None => 0,
    }
}

/// Kết thúc từ bằng ký tự ngắt. Trả độ dài text commit trong BUF.
#[no_mangle]
pub extern "C" fn demo_on_break(brk: u32) -> u32 {
    let c = char::from_u32(brk).unwrap_or(' ');
    let out = engine().on_break(c);
    write_buf(&out.text)
}

/// ESC: khôi phục raw. Trả độ dài trong BUF.
#[no_mangle]
pub extern "C" fn demo_escape() -> u32 {
    let s = engine().escape();
    write_buf(&s)
}

/// Con trỏ tới buffer tĩnh (đọc từ JS qua wasm memory).
#[no_mangle]
pub extern "C" fn demo_buf_ptr() -> *const u8 {
    unsafe { BUF.as_ptr() }
}
