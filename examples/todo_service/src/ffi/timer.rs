#![allow(unused_variables, dead_code)]
use crate::LlmllVal;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn now_ms(arg0: LlmllVal) -> LlmllVal {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis();
    LlmllVal::Int(now as i64)
}

pub fn now_iso(arg0: LlmllVal) -> LlmllVal {
    // Basic ISO format fallback to avoid chrono dep issues
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let hours = (now / 3600) % 24;
    let mins = (now / 60) % 60;
    let secs = now % 60;
    // Just a placeholder format for the demo
    LlmllVal::from(format!("1970-01-01T{:02}:{:02}:{:02}Z", hours, mins, secs))
}
