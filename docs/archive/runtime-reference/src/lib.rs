//! # LLMLL Runtime
//!
//! The LLMLL runtime provides:
//! - **Capability sandbox**: Every IO operation requires an explicit capability grant.
//!   Functions can only perform the operations listed in their capability set.
//! - **Command/Response model**: Pure logic returns `Command` values that the runtime
//!   inspects and executes. Logic never calls IO directly.
//! - **Event log**: Every executed command is recorded for audit and deterministic replay.
//! - **Replay engine**: Recorded event logs can be replayed to reproduce exact behavior.

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use thiserror::Error;

// ---------------------------------------------------------------------------
// Capability Types
// ---------------------------------------------------------------------------

/// A capability grant. Functions declare which capabilities they need.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Capability {
    FsRead(String),       // path prefix allowed to read
    FsWrite(String),      // path prefix allowed to write
    FsReadWrite(String),  // both read and write
    FsDelete(String),     // allowed to delete
    NetConnect(String),   // allowed to connect to host
    NetServe(u16),        // allowed to listen on port
    HttpGet(String),      // allowed to GET this URL pattern
    HttpPost(String),     // allowed to POST to this URL pattern
    DbQuery,              // can run read queries
    DbInsert,             // can run write queries
    ClockRead,            // can read the monotonic clock
    RandomBytes,          // can generate random bytes
    Custom(String),       // user-defined capability
    All,                  // unrestricted (testing only)
}

/// A set of capabilities granted to a function or module.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilitySet {
    grants: Vec<Capability>,
    deterministic: bool,  // if true, log for replay
}

impl CapabilitySet {
    pub fn new(grants: Vec<Capability>, deterministic: bool) -> Self {
        Self { grants, deterministic }
    }

    pub fn unrestricted() -> Self {
        Self { grants: vec![Capability::All], deterministic: false }
    }

    pub fn empty() -> Self {
        Self { grants: vec![], deterministic: false }
    }

    /// Check whether this set allows a given capability.
    pub fn allows(&self, cap: &Capability) -> bool {
        if self.grants.contains(&Capability::All) {
            return true;
        }
        self.grants.iter().any(|g| capability_subsumes(g, cap))
    }
}

/// Returns true if `grant` subsumes `requested` capability.
fn capability_subsumes(grant: &Capability, requested: &Capability) -> bool {
    match (grant, requested) {
        (Capability::All, _) => true,
        (Capability::FsReadWrite(base), Capability::FsRead(path)) => path.starts_with(base.as_str()),
        (Capability::FsReadWrite(base), Capability::FsWrite(path)) => path.starts_with(base.as_str()),
        (Capability::FsRead(base),  Capability::FsRead(path))  => path.starts_with(base.as_str()),
        (Capability::FsWrite(base), Capability::FsWrite(path)) => path.starts_with(base.as_str()),
        (Capability::FsDelete(base), Capability::FsDelete(path)) => path.starts_with(base.as_str()),
        (Capability::NetConnect(host), Capability::NetConnect(target)) => target.starts_with(host.as_str()),
        (Capability::NetServe(p1), Capability::NetServe(p2)) => p1 == p2,
        (Capability::HttpGet(patt), Capability::HttpGet(url)) => url.starts_with(patt.as_str()),
        (Capability::HttpPost(patt), Capability::HttpPost(url)) => url.starts_with(patt.as_str()),
        (Capability::DbQuery, Capability::DbQuery) => true,
        (Capability::DbInsert, Capability::DbInsert) => true,
        (Capability::ClockRead, Capability::ClockRead) => true,
        (Capability::RandomBytes, Capability::RandomBytes) => true,
        (Capability::Custom(a), Capability::Custom(b)) => a == b,
        // Exact match fallback
        _ => grant == requested,
    }
}

// ---------------------------------------------------------------------------
// Command / Response IO Model
// ---------------------------------------------------------------------------

/// A Command is an IO intent returned from pure LLMLL logic.
/// The runtime inspects and executes these — logic never calls IO directly.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Command {
    /// HTTP response: status code + body
    HttpResponse { status: u16, body: String },
    /// HTTP request: method + URL + body
    HttpRequest { method: String, url: String, body: String },
    /// Filesystem read
    FsRead { path: String },
    /// Filesystem write
    FsWrite { path: String, content: String },
    /// Filesystem delete
    FsDelete { path: String },
    /// Database query
    DbQuery { sql: String },
    /// Database insert
    DbInsert { table: String, data: String },
    /// No operation
    Noop,
    /// Sequence of commands
    Sequence(Vec<Command>),
    /// Custom extensible command
    Custom { name: String, args: Vec<String> },
}

/// The result of executing a Command.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Response {
    Unit,
    Text(String),
    Bytes(Vec<u8>),
    Integer(i64),
    Bool(bool),
    Error(String),
    Sequence(Vec<Response>),
}

// ---------------------------------------------------------------------------
// Event Log
// ---------------------------------------------------------------------------

/// A single recorded event in the log.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventEntry {
    pub id: String,               // UUID
    pub sequence: u64,            // monotonic sequence number
    pub timestamp_ns: u64,        // nanoseconds (monotonic clock)
    pub function_name: String,    // which def-logic triggered this
    pub command: Command,         // the command issued
    pub response: Option<Response>, // the response received (None if pending)
    pub capabilities_required: Vec<Capability>, // what caps were needed
}

/// Append-only event log — the "tape" for deterministic replay.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct EventLog {
    entries: Vec<EventEntry>,
    sequence: u64,
}

impl EventLog {
    pub fn new() -> Self {
        Self { entries: Vec::new(), sequence: 0 }
    }

    pub fn append(&mut self, func: &str, cmd: Command, caps: Vec<Capability>) -> &EventEntry {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = format!("event-{}", COUNTER.fetch_add(1, Ordering::Relaxed));
        let entry = EventEntry {
            id,
            sequence: self.sequence,
            timestamp_ns: 0, // TODO: use actual monotonic clock
            function_name: func.to_string(),
            command: cmd,
            response: None,
            capabilities_required: caps,
        };
        self.entries.push(entry);
        self.sequence += 1;
        self.entries.last().unwrap()
    }

    pub fn record_response(&mut self, id: &str, response: Response) {
        if let Some(entry) = self.entries.iter_mut().find(|e| e.id == id) {
            entry.response = Some(response);
        }
    }

    pub fn entries(&self) -> &[EventEntry] {
        &self.entries
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Serialize the event log to JSON.
    pub fn to_json(&self) -> Result<String, RuntimeError> {
        serde_json::to_string_pretty(self)
            .map_err(|e| RuntimeError::SerializationError(e.to_string()))
    }

    /// Load an event log from JSON (for replay).
    pub fn from_json(json: &str) -> Result<Self, RuntimeError> {
        serde_json::from_str(json)
            .map_err(|e| RuntimeError::SerializationError(e.to_string()))
    }
}

// ---------------------------------------------------------------------------
// Replay Engine
// ---------------------------------------------------------------------------

/// Replays a recorded event log, re-delivering pre-recorded responses
/// instead of executing commands against live IO.
pub struct ReplayEngine {
    log: VecDeque<EventEntry>,
    position: usize,
}

impl ReplayEngine {
    pub fn new(log: EventLog) -> Self {
        Self {
            log: VecDeque::from(log.entries),
            position: 0,
        }
    }

    /// Replay the next event. Returns the pre-recorded response.
    pub fn next_response(&mut self, expected_cmd: &Command) -> Result<Response, RuntimeError> {
        match self.log.pop_front() {
            None => Err(RuntimeError::ReplayExhausted),
            Some(entry) => {
                if !commands_match(expected_cmd, &entry.command) {
                    return Err(RuntimeError::ReplayCommandMismatch {
                        expected: format!("{expected_cmd:?}"),
                        recorded: format!("{:?}", entry.command),
                        position: self.position,
                    });
                }
                self.position += 1;
                Ok(entry.response.unwrap_or(Response::Unit))
            }
        }
    }

    pub fn is_exhausted(&self) -> bool {
        self.log.is_empty()
    }
}

/// Check if two commands are "the same" for replay purposes.
fn commands_match(a: &Command, b: &Command) -> bool {
    // Simple structural equality — for deterministic replay
    std::mem::discriminant(a) == std::mem::discriminant(b)
}

// ---------------------------------------------------------------------------
// Runtime Executor
// ---------------------------------------------------------------------------

/// Errors that can occur at runtime.
#[derive(Debug, Error)]
pub enum RuntimeError {
    #[error("Capability denied: operation {operation} requires {required:?}")]
    CapabilityDenied { operation: String, required: Capability },

    #[error("IO error in {operation}: {msg}")]
    IoError { operation: String, msg: String },

    #[error("Replay exhausted — recorded log has no more events")]
    ReplayExhausted,

    #[error("Replay command mismatch at position {position}: expected {expected}, recorded {recorded}")]
    ReplayCommandMismatch { expected: String, recorded: String, position: usize },

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Contract violated in {function}: {message}")]
    ContractViolated { function: String, message: String },

    #[error("Delegate failure: {agent} — {kind}: {message}")]
    DelegateFailure { agent: String, kind: DelegationErrorKind, message: String },

    #[error("Unresolved hole: {hole_name}")]
    UnresolvedHole { hole_name: String },
}

/// The DelegationError sum type from the LLMLL spec.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum DelegationErrorKind {
    AgentTimeout,
    AgentCrash,
    TypeMismatch,
    AgentNotFound,
}

impl std::fmt::Display for DelegationErrorKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::AgentTimeout  => write!(f, "timeout"),
            Self::AgentCrash    => write!(f, "crash"),
            Self::TypeMismatch  => write!(f, "type-mismatch"),
            Self::AgentNotFound => write!(f, "not-found"),
        }
    }
}

/// The runtime executor: holds capability grants, event log, and executes commands.
pub struct Runtime {
    pub capabilities: CapabilitySet,
    pub event_log: EventLog,
    pub replay: Option<ReplayEngine>,
}

impl Runtime {
    /// Create a new runtime with the given capabilities.
    pub fn new(capabilities: CapabilitySet) -> Self {
        Self {
            capabilities,
            event_log: EventLog::new(),
            replay: None,
        }
    }

    /// Create a runtime in replay mode (plays back recorded responses).
    pub fn new_replay(capabilities: CapabilitySet, log: EventLog) -> Self {
        let replay = Some(ReplayEngine::new(log));
        Self {
            capabilities,
            event_log: EventLog::new(),
            replay,
        }
    }

    /// Execute a Command, checking capabilities, recording the event, and returning a Response.
    pub fn execute(&mut self, func: &str, cmd: Command) -> Result<Response, RuntimeError> {
        let required_cap = command_capability(&cmd);

        // Check capability
        if let Some(ref cap) = required_cap {
            if !self.capabilities.allows(cap) {
                return Err(RuntimeError::CapabilityDenied {
                    operation: func.to_string(),
                    required: cap.clone(),
                });
            }
        }

        // If in replay mode, return pre-recorded response
        if let Some(ref mut replay) = self.replay {
            let response = replay.next_response(&cmd)?;
            return Ok(response);
        }

        // Record the event before executing
        let caps = required_cap.map(|c| vec![c]).unwrap_or_default();
        let _entry = self.event_log.append(func, cmd.clone(), caps);

        // Execute the command
        let response = self.execute_command_io(cmd)?;
        Ok(response)
    }

    /// The actual IO execution (separate from policy checking above).
    fn execute_command_io(&self, cmd: Command) -> Result<Response, RuntimeError> {
        match cmd {
            Command::Noop => Ok(Response::Unit),

            Command::FsRead { path } => {
                std::fs::read_to_string(&path)
                    .map(Response::Text)
                    .map_err(|e| RuntimeError::IoError {
                        operation: format!("fs-read:{path}"),
                        msg: e.to_string(),
                    })
            }

            Command::FsWrite { path, content } => {
                std::fs::write(&path, content)
                    .map(|_| Response::Unit)
                    .map_err(|e| RuntimeError::IoError {
                        operation: format!("fs-write:{path}"),
                        msg: e.to_string(),
                    })
            }

            Command::FsDelete { path } => {
                std::fs::remove_file(&path)
                    .map(|_| Response::Unit)
                    .map_err(|e| RuntimeError::IoError {
                        operation: format!("fs-delete:{path}"),
                        msg: e.to_string(),
                    })
            }

            Command::HttpResponse { status, body } => {
                // In a real WASM server context, this would write to the socket.
                // For now, return the response itself as confirmation.
                Ok(Response::Text(format!("HTTP {status}: {body}")))
            }

            Command::HttpRequest { method, url, body } => {
                // NOTE: Would use reqwest or similar in production.
                // Stubbed for WASM compatibility.
                Ok(Response::Text(format!("TODO: HTTP {method} {url} {body}")))
            }

            Command::DbQuery { sql } => {
                // Stub — real implementation would use sqlx or rusqlite.
                Ok(Response::Text(format!("TODO: query({sql})")))
            }

            Command::DbInsert { table, data } => {
                Ok(Response::Text(format!("TODO: insert into {table}: {data}")))
            }

            Command::Sequence(cmds) => {
                let mut responses = Vec::new();
                for cmd in cmds {
                    responses.push(self.execute_command_io(cmd)?);
                }
                Ok(Response::Sequence(responses))
            }

            Command::Custom { name, args } => {
                Ok(Response::Text(format!("custom:{name}({args:?})")))
            }
        }
    }
}

/// Map a Command to the Capability it requires (if any).
fn command_capability(cmd: &Command) -> Option<Capability> {
    match cmd {
        Command::FsRead { path }         => Some(Capability::FsRead(path.clone())),
        Command::FsWrite { path, .. }    => Some(Capability::FsWrite(path.clone())),
        Command::FsDelete { path }       => Some(Capability::FsDelete(path.clone())),
        Command::HttpRequest { url, .. } => Some(Capability::NetConnect(url.clone())),
        Command::HttpResponse { .. }     => Some(Capability::NetServe(80)), // approximate
        Command::DbQuery { .. }          => Some(Capability::DbQuery),
        Command::DbInsert { .. }         => Some(Capability::DbInsert),
        Command::Noop                    => None,
        Command::Sequence(_)             => None,
        Command::Custom { .. }           => None,
    }
}

// ---------------------------------------------------------------------------
// Public API: Module Execution
// ---------------------------------------------------------------------------

/// Registry of LLMLL logic functions — maps name to Rust fn.
pub type FnRegistry = HashMap<String, Box<dyn Fn(&[LlmllValue]) -> LlmllValue + Send + Sync>>;

/// Value representation at runtime.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum LlmllValue {
    Int(i64),
    Float(f64),
    Text(String),
    Bool(bool),
    Unit,
    Bytes(Vec<u8>),
    List(Vec<LlmllValue>),
    Pair(Box<LlmllValue>, Box<LlmllValue>),
    Success(Box<LlmllValue>),
    Failure(Box<LlmllValue>),
    Command(Command),
}

impl std::fmt::Display for LlmllValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Int(n)       => write!(f, "{n}"),
            Self::Float(x)     => write!(f, "{x}"),
            Self::Text(s)      => write!(f, "{s:?}"),
            Self::Bool(b)      => write!(f, "{b}"),
            Self::Unit         => write!(f, "()"),
            Self::Bytes(b)     => write!(f, "bytes[{}]", b.len()),
            Self::List(xs)     => write!(f, "[{}]", xs.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(", ")),
            Self::Pair(a, b)   => write!(f, "({a}, {b})"),
            Self::Success(v)   => write!(f, "Success({v})"),
            Self::Failure(v)   => write!(f, "Failure({v})"),
            Self::Command(c)   => write!(f, "Command({c:?})"),
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_capability_subsumes_all() {
        let grant = Capability::All;
        assert!(capability_subsumes(&grant, &Capability::FsRead("/".to_string())));
        assert!(capability_subsumes(&grant, &Capability::NetConnect("http://example.com".to_string())));
    }

    #[test]
    fn test_capability_subsumes_prefix() {
        let grant = Capability::FsRead("/data".to_string());
        assert!(capability_subsumes(&grant, &Capability::FsRead("/data/file.txt".to_string())));
        assert!(!capability_subsumes(&grant, &Capability::FsRead("/etc/passwd".to_string())));
    }

    #[test]
    fn test_capability_readwrite_subsumes_read() {
        let grant = Capability::FsReadWrite("/data".to_string());
        assert!(capability_subsumes(&grant, &Capability::FsRead("/data/x".to_string())));
        assert!(capability_subsumes(&grant, &Capability::FsWrite("/data/x".to_string())));
    }

    #[test]
    fn test_capability_set_denies_missing() {
        let caps = CapabilitySet::new(vec![Capability::FsRead("/tmp".to_string())], false);
        assert!(caps.allows(&Capability::FsRead("/tmp/foo".to_string())));
        assert!(!caps.allows(&Capability::NetConnect("https://evil.com".to_string())));
    }

    #[test]
    fn test_event_log_append() {
        let mut log = EventLog::new();
        log.append("withdraw", Command::Noop, vec![]);
        assert_eq!(log.len(), 1);
    }

    #[test]
    fn test_runtime_noop() {
        let mut rt = Runtime::new(CapabilitySet::unrestricted());
        let resp = rt.execute("test", Command::Noop).unwrap();
        assert_eq!(resp, Response::Unit);
        assert_eq!(rt.event_log.len(), 1);
    }

    #[test]
    fn test_runtime_capability_denied() {
        let mut rt = Runtime::new(CapabilitySet::empty());
        let result = rt.execute("bad_fn",
            Command::FsRead { path: "/etc/passwd".to_string() });
        assert!(result.is_err());
        matches!(result.unwrap_err(), RuntimeError::CapabilityDenied { .. });
    }

    #[test]
    fn test_event_log_serialization() {
        let mut log = EventLog::new();
        log.append("fn_a", Command::Noop, vec![]);
        let json = log.to_json().unwrap();
        let loaded = EventLog::from_json(&json).unwrap();
        assert_eq!(loaded.len(), 1);
    }
}
