// FFI implementation for 'atomic_fs' — atomic file I/O
// Uses write-to-temp-then-rename for crash-safe persistence.
#![allow(unused_variables, dead_code)]
use crate::LlmllVal;
use std::fs;
use std::io::Write;
use std::path::Path;

/// Write `content` to `path` atomically:
/// 1. Write to a sibling `.tmp` file
/// 2. fsync the tmp file
/// 3. rename (atomic on POSIX) over the target
pub fn atomic_write(path: LlmllVal, content: LlmllVal) -> LlmllVal {
    let path_str = path.as_str().to_string();
    let content_str = content.as_str().to_string();

    let tmp_path = format!("{}.tmp", path_str);
    let result = (|| -> std::io::Result<()> {
        // Ensure parent directory exists
        if let Some(parent) = Path::new(&path_str).parent() {
            fs::create_dir_all(parent)?;
        }
        let mut f = fs::File::create(&tmp_path)?;
        f.write_all(content_str.as_bytes())?;
        f.sync_all()?;
        drop(f);
        fs::rename(&tmp_path, &path_str)?;
        Ok(())
    })();

    LlmllVal::Bool(result.is_ok())
}

/// Read file contents; returns empty string on any error (missing file etc.)
pub fn read_file_safe(path: LlmllVal) -> LlmllVal {
    let content = fs::read_to_string(path.as_str()).unwrap_or_default();
    LlmllVal::Text(content)
}

/// Returns true if the file exists and is a regular file
pub fn file_exists(path: LlmllVal) -> LlmllVal {
    LlmllVal::Bool(Path::new(path.as_str()).is_file())
}
