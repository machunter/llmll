use std::convert::Infallible;
use std::fs;
use std::sync::{Arc, Mutex};
use hyper::{Body, Request, Response, Server, Method, StatusCode};
use hyper::service::{make_service_fn, service_fn};
use todo::*;

#[tokio::main]
async fn main() {
    let file_path = "data.json";
    
    // Load initial state
    let json_data = fs::read_to_string(file_path).unwrap_or_else(|_| "[]".to_string());
    let tasks_val = ffi::todo_json::parse_tasks(LlmllVal::from(json_data));
    let state_val = LlmllVal::from((tasks_val, LlmllVal::from(file_path.to_string())));
    
    let state = Arc::new(Mutex::new(state_val));
    
    let addr = ([0, 0, 0, 0], 8080).into();

    let make_svc = make_service_fn(move |_| {
        let state = Arc::clone(&state);
        async move {
            Ok::<_, Infallible>(service_fn(move |req| {
                let state = Arc::clone(&state);
                async move { handle_http(state, req).await }
            }))
        }
    });

    println!("Todo Service listening on http://127.0.0.1:8080");
    if let Err(e) = Server::bind(&addr).serve(make_svc).await {
        eprintln!("server error: {}", e);
    }
}

async fn handle_http(
    state: Arc<Mutex<LlmllVal>>,
    req: Request<Body>,
) -> Result<Response<Body>, Infallible> {
    let method = match *req.method() {
        Method::GET => LlmllVal::Adt("GET".to_string(), vec![LlmllVal::Unit]),
        Method::POST => LlmllVal::Adt("POST".to_string(), vec![LlmllVal::Unit]),
        Method::PUT => LlmllVal::Adt("PUT".to_string(), vec![LlmllVal::Unit]),
        Method::DELETE => LlmllVal::Adt("DELETE".to_string(), vec![LlmllVal::Unit]),
        _ => return Ok(Response::builder()
                .status(StatusCode::METHOD_NOT_ALLOWED)
                .body(Body::empty())
                .unwrap()),
    };

    let path = LlmllVal::from(req.uri().path().to_string());
    
    let body_bytes = hyper::body::to_bytes(req.into_body()).await.unwrap_or_default();
    let body_str = String::from_utf8_lossy(&body_bytes).to_string();
    let body = LlmllVal::from(body_str);

    let llmll_req = LlmllVal::from((method, (path, body)));

    let result = {
        let st = state.lock().unwrap().clone();
        handle_request(st, llmll_req)
    };

    let new_state = first(result.clone());
    let llmll_res = second(result);

    // Update state and save
    {
        let mut guard = state.lock().unwrap();
        if *guard != new_state {
            *guard = new_state.clone();
            // Save to disk
            let new_tasks = first(new_state.clone());
            let new_json = ffi::todo_json::stringify_tasks(new_tasks).into_string();
            // Atomic file write using our FFI (which just does tempfile rename)
            ffi::atomic_fs::atomic_write(
                LlmllVal::from("data.json".to_string()),
                LlmllVal::from(new_json)
            );
        }
    }

    let status_code = first(llmll_res.clone()).as_int() as u16;
    let res_body = second(llmll_res).into_string();

    let mut response = Response::new(Body::from(res_body));
    *response.status_mut() = StatusCode::from_u16(status_code).unwrap_or(StatusCode::OK);

    Ok(response)
}
