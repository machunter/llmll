// FFI implementation for 'http_server' — HTTP server using tiny_http
// Implements request parsing and response writing for the tasks REST service.
#![allow(unused_variables, dead_code, clippy::all)]
use crate::LlmllVal;

// ---------------------------------------------------------------------------
// These functions are called by the LLMLL-generated logic.
// In the main harness (main.rs) we drive tiny_http directly, so these
// helpers are used to extract fields from the serialised request JSON that
// main.rs stores in thread-local storage before calling the logic.
// ---------------------------------------------------------------------------

use std::cell::RefCell;
use serde_json::Value;

thread_local! {
    /// The current request is stashed here by main.rs before calling handle_request.
    static CURRENT_REQUEST: RefCell<Value> = RefCell::new(serde_json::json!({}));
    /// The HTTP response produced by handle_request is stashed here so main.rs can send it.
    static PENDING_RESPONSE: RefCell<(u16, String)> = RefCell::new((200, String::new()));
}

/// Called by main.rs to install the current request before invoking the logic.
pub fn set_current_request(method: &str, path: &str, body: &str) {
    CURRENT_REQUEST.with(|r| {
        *r.borrow_mut() = serde_json::json!({
            "method": method,
            "path": path,
            "body": body
        });
    });
}

/// Called by main.rs to retrieve the response after the logic has run.
pub fn take_pending_response() -> (u16, String) {
    PENDING_RESPONSE.with(|r| r.borrow().clone())
}

// ---------------------------------------------------------------------------
// LLMLL FFI functions — called from generated lib.rs
// ---------------------------------------------------------------------------

/// Extract the HTTP method from the stashed request. arg0 is the raw request
/// string (unused — we use thread-local storage instead).
pub fn get_method(arg0: LlmllVal) -> LlmllVal {
    let method = CURRENT_REQUEST.with(|r| {
        r.borrow()["method"].as_str().unwrap_or("GET").to_string()
    });
    LlmllVal::Text(method)
}

pub fn get_path(arg0: LlmllVal) -> LlmllVal {
    let path = CURRENT_REQUEST.with(|r| {
        r.borrow()["path"].as_str().unwrap_or("/").to_string()
    });
    LlmllVal::Text(path)
}

pub fn get_body(arg0: LlmllVal) -> LlmllVal {
    let body = CURRENT_REQUEST.with(|r| {
        r.borrow()["body"].as_str().unwrap_or("{}").to_string()
    });
    LlmllVal::Text(body)
}

/// Format and stash the HTTP response so main.rs can send it.
/// Returns the formatted response string (also written to PENDING_RESPONSE).
pub fn http_response(status: LlmllVal, body: LlmllVal) -> LlmllVal {
    let status_code = status.as_int() as u16;
    let body_str = body.as_str().to_string();
    PENDING_RESPONSE.with(|r| {
        *r.borrow_mut() = (status_code, body_str.clone());
    });
    LlmllVal::Text(body_str)
}
