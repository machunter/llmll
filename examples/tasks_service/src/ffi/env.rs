// FFI implementation for 'env' — CLI argument parsing
// Parses --port <N> and --file <path> from the process args string.
#![allow(unused_variables, dead_code)]
use crate::LlmllVal;

/// The LLMLL `init` function receives the full CLI args as a single string
/// (everything after the binary name, space-joined by the main harness).
/// We parse it here using standard env::args() directly, ignoring the arg0 dummy.

pub fn parse_port(_arg0: LlmllVal) -> LlmllVal {
    let args: Vec<String> = std::env::args().collect();
    let port = args
        .windows(2)
        .find(|w| w[0] == "--port")
        .and_then(|w| w[1].parse::<i64>().ok())
        .unwrap_or(8080);
    LlmllVal::Int(port)
}

pub fn parse_file_path(_arg0: LlmllVal) -> LlmllVal {
    let args: Vec<String> = std::env::args().collect();
    let path = args
        .windows(2)
        .find(|w| w[0] == "--file")
        .map(|w| w[1].clone())
        .unwrap_or_else(|| "./data.json".to_string());
    LlmllVal::Text(path)
}
