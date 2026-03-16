# Todo Service implementation Notes (LLMLL v0.1.1)

This document summarizes the technical difficulties encountered while implementing the Todo List REST Service and the strategies used to overcome them.

## 1. Structured IO / HTTP Parsing
**Difficulty**: LLMLL v0.1.1 lacks built-in support for structured HTTP request parsing (headers, methods, paths) and JSON serialization.
**Solution**: 
- Replaced the built-in `def-main :http` harness with a custom `src/main.rs`.
- Used the `hyper` and `tokio` Rust crates to drive the networking layer.
- Implemented FFI stubs (`rust.serde_json`) to handle the conversion between `LlmllVal` and structured JSON.

## 2. Type System Constraints (Pair Types)
**Difficulty**: The LLMLL parser rejects tuple/pair types (e.g., `(string, int)`) in function parameters and type definitions.
**Solution**: 
- Declared Custom ADTs with a `unit` payload: `(type HttpRequest (| Req unit))`.
- Used the dynamically-typed nature of LLMLL at runtime to pass nested pairs into these "untyped" constructors.
- Leveraged accessor functions (`first`, `second`) to extract data fields within logic functions.

## 3. FFI Crate Resolution & Cargo.toml
**Difficulty**: The compiler automatically adds FFI names (like `rust.todo_json`) as literal dependencies in `Cargo.toml`, causing build failures when these aren't real crates on `crates.io`.
**Solution**: 
- Manually purged imaginary dependencies from the generated `Cargo.toml`.
- Specific pinned versions for `tokio`, `hyper`, and `indexmap` were added to ensure compatibility with the host Rust toolchain (v1.78).

## 4. FFI Stub Code Generation
**Difficulty**: The `llmll build` tool generates `use crate_name;` at the top of FFI stubs, which is an invalid import for internal FFI modules.
**Solution**: Proactively edited the `src/ffi/*.rs` files to remove these injected imports after transpilation.

## 5. List Operations
**Difficulty**: No native `list-filter` or `list-remove` built-ins.
**Solution**: Implemented a filtering pattern using `list-fold` and `list-append` to rebuild task lists during DELETE operations.

---
*Created on 2026-03-16*
