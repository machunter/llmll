// FFI implementation for 'serde_json' — Task JSON marshalling
// Uses serde_json crate for all JSON operations.
#![allow(unused_variables, dead_code, clippy::all)]
use crate::LlmllVal;
use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Parse the tasks JSON string (a JSON array) into a Vec<Value>.
fn parse_tasks(s: &str) -> Vec<Value> {
    serde_json::from_str::<Vec<Value>>(s).unwrap_or_default()
}

/// Serialise a Vec<Value> of tasks back to a JSON array string.
fn serialise_tasks(tasks: &[Value]) -> String {
    serde_json::to_string(tasks).unwrap_or_else(|_| "[]".to_string())
}

/// Current UTC timestamp as ISO-8601 string (second precision).
fn utc_now() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // Format manually — no chrono dependency required
    let (y, mo, d, h, mi, s) = epoch_to_parts(secs);
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, mo, d, h, mi, s)
}

fn epoch_to_parts(mut s: u64) -> (u64, u64, u64, u64, u64, u64) {
    let sec = s % 60; s /= 60;
    let min = s % 60; s /= 60;
    let hour = s % 24; s /= 24;
    // Days since 1970-01-01
    let mut days = s;
    let mut year = 1970u64;
    loop {
        let days_in_year = if is_leap(year) { 366 } else { 365 };
        if days < days_in_year { break; }
        days -= days_in_year;
        year += 1;
    }
    let month_days: Vec<u64> = vec![
        31, if is_leap(year) { 29 } else { 28 }, 31, 30, 31, 30,
        31, 31, 30, 31, 30, 31,
    ];
    let mut month = 1u64;
    for &md in &month_days {
        if days < md { break; }
        days -= md;
        month += 1;
    }
    (year, month, days + 1, hour, min, sec)
}

fn is_leap(y: u64) -> bool { y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) }

// ---------------------------------------------------------------------------
// Dispatch helper shared by tasks_from_json and task_from_json
// ---------------------------------------------------------------------------

/// `tasks_from_json` receives a JSON object of the form:
///   { "op": "add" | "complete" | "delete" | "get" | "field", ... }
/// and returns the updated tasks JSON array string (or field value string).
pub fn tasks_from_json(arg0: LlmllVal) -> LlmllVal {
    let s = arg0.as_str();
    let v: Value = serde_json::from_str(s).unwrap_or(Value::Null);
    let op = v["op"].as_str().unwrap_or("");

    // "tasks" field may be a JSON string containing the array, or an embedded array
    let tasks_val = &v["tasks"];
    let tasks_str = if let Some(s) = tasks_val.as_str() {
        s.to_string()
    } else {
        tasks_val.to_string()
    };
    let mut tasks = parse_tasks(&tasks_str);

    let updated = match op {
        "add" => {
            let task_val = &v["task"];
            // task may be an embedded JSON object (parsed inline from the concat string)
            // or a JSON-encoded string — handle both
            let task_obj: Value = if task_val.is_object() {
                task_val.clone()
            } else if let Some(s) = task_val.as_str() {
                serde_json::from_str(s).unwrap_or_else(|_| task_val.clone())
            } else {
                task_val.clone()
            };
            tasks.push(task_obj);
            serialise_tasks(&tasks)
        }
        "complete" => {
            let id = v["id"].as_i64().unwrap_or(-1);
            let completed_at = v["completed_at"].as_str().unwrap_or("").to_string();
            for t in tasks.iter_mut() {
                if t["id"].as_i64() == Some(id) {
                    t["done"] = json!(true);
                    t["completed_at"] = json!(completed_at);
                }
            }
            serialise_tasks(&tasks)
        }
        "delete" => {
            let id = v["id"].as_i64().unwrap_or(-1);
            tasks.retain(|t| t["id"].as_i64() != Some(id));
            serialise_tasks(&tasks)
        }
        _ => serialise_tasks(&tasks),
    };

    LlmllVal::Text(updated)
}

/// Serialise the tasks JSON array string to a pretty JSON array string.
pub fn tasks_to_json(arg0: LlmllVal) -> LlmllVal {
    // arg0 is already a JSON array string; re-serialise as compact JSON
    let s = arg0.as_str();
    let v: Value = serde_json::from_str(s).unwrap_or(json!([]));
    LlmllVal::Text(v.to_string())
}

/// `task_from_json` handles single-task lookups and field extraction.
/// Receives a JSON object: { "op": "get" | "field", "id"?: int, "field"?: string, "data"?: object, "tasks"?: string }
pub fn task_from_json(arg0: LlmllVal) -> LlmllVal {
    let s = arg0.as_str();
    let v: Value = serde_json::from_str(s).unwrap_or(Value::Null);
    let op = v["op"].as_str().unwrap_or("");

    let result = match op {
        "get" => {
            let id = v["id"].as_i64().unwrap_or(-1);
            // tasks may be an embedded array or a string
            let tasks_val = &v["tasks"];
            let tasks = if tasks_val.is_array() {
                tasks_val.as_array().cloned().unwrap_or_default()
            } else {
                parse_tasks(tasks_val.as_str().unwrap_or("[]"))
            };
            tasks
                .into_iter()
                .find(|t| t["id"].as_i64() == Some(id))
                .map(|t| t.to_string())
                .unwrap_or_default()
        }
        "field" => {
            // Extract a single field from a request body — data may be embedded or string
            let field = v["field"].as_str().unwrap_or("");
            let data_val = &v["data"];
            let data: Value = if data_val.is_object() {
                data_val.clone()
            } else if let Some(s) = data_val.as_str() {
                serde_json::from_str(s).unwrap_or(Value::Null)
            } else {
                Value::Null
            };
            // Return the field value as a string (unwrap if it's a JSON string)
            match &data[field] {
                Value::String(s) => s.clone(),
                Value::Null => String::new(),
                other => other.to_string(),
            }
        }
        _ => String::new(),
    };

    LlmllVal::Text(result)
}

/// Serialise a single task object (JSON object string) to JSON.
pub fn task_to_json(arg0: LlmllVal) -> LlmllVal {
    arg0 // already a JSON string
}

/// Return the next available integer ID given the current tasks JSON array string.
pub fn next_id(arg0: LlmllVal) -> LlmllVal {
    let tasks = parse_tasks(arg0.as_str());
    let max_id = tasks
        .iter()
        .filter_map(|t| t["id"].as_i64())
        .max()
        .unwrap_or(0);
    LlmllVal::Int(max_id + 1)
}

/// Return the current UTC timestamp as an ISO-8601 string. Ignores arg0.
pub fn now_timestamp(_arg0: LlmllVal) -> LlmllVal {
    LlmllVal::Text(utc_now())
}

/// Extract the integer ID from a URL path like "/tasks/42".
/// Returns 0 if not parseable.
pub fn id_from_path(arg0: LlmllVal) -> LlmllVal {
    let path = arg0.as_str();
    let id = path
        .rsplit('/')
        .next()
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(0);
    LlmllVal::Int(id)
}
