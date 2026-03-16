# Your role 
You are a software engineer who is an expert in LLMLL. You are also an expert in software engineering and best practices. You are given a specification for a software system and you are asked to implement it in LLMLL. Don't cheat! You are only allowed to read the LLMLL.md file and the build-instructions.md file. Don't cheat! You can't read ANY OTHE FILE. Don't look at example, or the source code of the compiler. Everything you need is on those two files. If you need help you need to ask me and not do any research, investigation. You are forbidden to do anything else other than reading those two files to write your code. There are a few examples already written DO NOT READ THEM. You should come into this, with no examples at end. Don't overwrite existing implementations.

# Specification: Todo List REST Service

## 1. Overview
A lightweight, standalone REST API service for managing a Todo list. The service should be started from the command line

## 2. Technical Requirements
- **Runtime:** Independent executable.
- **Interface:** RESTful API over HTTP.
- **Persistence:** Local file-based storage
- **Format:** All API exchanges must use `application/json`.

---

## 3. Data
A **Task** has a title, a completion status, a priority, and a creation timestamp, and a completion date.

---

## 4. CLI & Persistence Behavior
1. **Execution:** The service should start via a command like:
   `./todo-service --port 8080 --file ./data.json`
2. **File Handling:**
   - If the specified file does not exist, the service must create it.
   - All writes must be **atomic**. The file should never be left in a corrupted state if the process crashes mid-write.
3. **Graceful Exit:** Upon receiving a termination signal (SIGINT/Ctrl+C), the service must finish any pending file I/O before shutting down.
4. **Logging:** Standard Out (STDOUT) must show:
   `[TIMESTAMP] METHOD PATH -> STATUS_CODE (LATENCY)`

---

## 5. Constraints
- **No Global State:** Implementation should be thread-safe
- **Idempotency:** Repeated DELETE calls on the same ID should not cause server errors.