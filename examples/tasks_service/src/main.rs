// main.rs — Tasks Service event loop
//
// Drives tiny_http, wires each request through the LLMLL-generated
// handle_request logic, and sends the response back over HTTP.
//
// Signal handling (SIGINT/Ctrl-C) uses ctrlc crate for graceful shutdown —
// satisfying the spec's "finish any pending I/O before shutting down" requirement.

use std::io::Read;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tiny_http::{Header, Response, Server};
use tasks_service::ffi::http_server::{set_current_request, take_pending_response};
use tasks_service::{init, handle_request};
use tasks_service::LlmllVal;

fn main() {
    // -----------------------------------------------------------------------
    // 1. Parse CLI args and initialise AppState via LLMLL init logic
    // -----------------------------------------------------------------------
    // Collect all args after the binary name into a single space-joined string
    // (the LLMLL init function receives this but our FFI impl uses env::args()
    // directly, so we can pass anything here).
    let args_str = std::env::args().skip(1).collect::<Vec<_>>().join(" ");
    let mut state = init(LlmllVal::Text(args_str));

    // Extract the port from state (first element of the AppState pair)
    let port = match &state {
        LlmllVal::Pair(fst, _) => fst.as_int() as u16,
        _ => 8080,
    };

    // -----------------------------------------------------------------------
    // 2. Start HTTP server
    // -----------------------------------------------------------------------
    let addr = format!("0.0.0.0:{}", port);
    let server = Arc::new(
        Server::http(&addr).unwrap_or_else(|e| panic!("Could not bind to {}: {}", addr, e)),
    );
    println!("Tasks service listening on http://{}", addr);

    // -----------------------------------------------------------------------
    // 3. Graceful shutdown flag (Ctrl-C / SIGINT)
    // -----------------------------------------------------------------------
    let running = Arc::new(AtomicBool::new(true));
    {
        let running = Arc::clone(&running);
        ctrlc::set_handler(move || {
            println!("\nShutdown signal received — finishing pending I/O...");
            running.store(false, Ordering::SeqCst);
        })
        .expect("Error setting Ctrl-C handler");
    }

    // -----------------------------------------------------------------------
    // 4. Request loop
    // -----------------------------------------------------------------------
    loop {
        if !running.load(Ordering::SeqCst) {
            println!("Tasks service stopped cleanly.");
            break;
        }

        // Non-blocking recv with 100ms timeout so we check the shutdown flag
        let mut request = match server.recv_timeout(std::time::Duration::from_millis(100)) {
            Ok(Some(req)) => req,
            Ok(None) => continue,  // timeout — check shutdown flag
            Err(e) => {
                eprintln!("HTTP recv error: {}", e);
                continue;
            }
        };

        let method = request.method().to_string();
        let path = request.url().to_string();

        // Read request body
        let mut body = String::new();
        let _ = request.as_reader().read_to_string(&mut body);

        // Stash request fields for the FFI functions to pick up
        set_current_request(&method, &path, &body);

        // Call the LLMLL-generated handle_request:
        //   handle_request(state, raw_request) -> (new_state, Command)
        // We pass an empty string as raw_request; the FFI reads from TLS.
        let result = handle_request(state.clone(), LlmllVal::Text(String::new()));

        // Extract new_state from the returned pair
        if let LlmllVal::Pair(new_state, _cmd) = result {
            state = *new_state;
        }

        // Read the response that http_response() stashed in TLS
        let (status_code, body_str) = take_pending_response();

        let content_type = Header::from_bytes(
            &b"Content-Type"[..],
            &b"application/json"[..],
        )
        .unwrap();

        let response = Response::from_string(body_str)
            .with_status_code(status_code)
            .with_header(content_type);

        if let Err(e) = request.respond(response) {
            eprintln!("Failed to send response: {}", e);
        }
    }
}
