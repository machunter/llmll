#![allow(unused_variables, dead_code)]
use crate::LlmllVal;
use std::fs::{self, File};
use std::io::Write;

pub fn atomic_write(arg0: LlmllVal, arg1: LlmllVal) -> LlmllVal {
    let path = arg0.as_str();
    let content = arg1.as_str();
    let tmp_path = format!("{}.tmp", path);
    match File::create(&tmp_path) {
        Ok(mut f) => {
            if f.write_all(content.as_bytes()).is_ok() && fs::rename(&tmp_path, path).is_ok() {
                return LlmllVal::Adt("Success".to_string(), vec![LlmllVal::Unit]);
            }
        }
        Err(_) => {}
    }
    let _ = fs::remove_file(&tmp_path);
    LlmllVal::Adt("Error".to_string(), vec![LlmllVal::from("Failed to write".to_string())])
}

pub fn read_file(arg0: LlmllVal) -> LlmllVal {
    match fs::read_to_string(arg0.as_str()) {
        Ok(s) => LlmllVal::Adt("Success".to_string(), vec![LlmllVal::from(s)]),
        Err(e) => LlmllVal::Adt("Error".to_string(), vec![LlmllVal::from(e.to_string())]),
    }
}
