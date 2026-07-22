//! Generate `include/dau_core.h` via cbindgen when building the crate.

use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

fn main() {
    let crate_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let config_path = crate_dir.join("cbindgen.toml");
    let out_dir = crate_dir.join("include");
    let header_path = out_dir.join("dau_core.h");

    // Rebuild header when FFI surface or config changes.
    println!("cargo:rerun-if-changed=src/ffi.rs");
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=src/config.rs");
    println!("cargo:rerun-if-changed=src/engine/mod.rs");
    println!("cargo:rerun-if-changed=cbindgen.toml");
    println!("cargo:rerun-if-changed=build.rs");

    if let Err(e) = fs::create_dir_all(&out_dir) {
        println!("cargo:warning=could not create include/: {e}");
        return;
    }

    let config = match cbindgen::Config::from_file(&config_path) {
        Ok(c) => c,
        Err(e) => {
            println!("cargo:warning=cbindgen.toml: {e}");
            cbindgen::Config::default()
        }
    };

    let bindings = match cbindgen::Builder::new()
        .with_crate(&crate_dir)
        .with_config(config)
        .generate()
    {
        Ok(b) => b,
        Err(e) => {
            println!("cargo:warning=cbindgen generate failed: {e}");
            return;
        }
    };

    // Atomic-ish write: generate to memory, skip if unchanged, else write temp + rename.
    // cbindgen 0.27: `write` returns `()`.
    let mut generated = Vec::new();
    bindings.write(&mut generated);

    if let Ok(existing) = fs::read(&header_path) {
        if existing == generated {
            return;
        }
    }

    let tmp_path = out_dir.join("dau_core.h.tmp");
    match fs::File::create(&tmp_path).and_then(|mut f| {
        f.write_all(&generated)?;
        f.sync_all()
    }) {
        Ok(()) => {
            if let Err(e) = fs::rename(&tmp_path, &header_path) {
                // Fallback: direct write if rename fails (e.g. cross-device).
                if let Err(e2) = fs::write(&header_path, &generated) {
                    println!(
                        "cargo:warning=failed to write {}: rename={e}, write={e2}",
                        header_path.display()
                    );
                }
                let _ = fs::remove_file(&tmp_path);
            }
        }
        Err(e) => {
            println!("cargo:warning=failed to write temp header: {e}");
            if let Err(e2) = fs::write(&header_path, &generated) {
                println!(
                    "cargo:warning=failed to write {}: {e2}",
                    header_path.display()
                );
            }
        }
    }
}
