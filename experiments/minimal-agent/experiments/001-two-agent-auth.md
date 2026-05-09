# Two-Agent Auth Module

**Difficulty:** ★☆☆
**v0.3 features exercised:** `def-interface`, `?delegate` (blocking), `on-failure`, `DelegationError`

## Specification

Build a user authentication module for a simple web service. The system has two agents:

- **Lead Agent** — owns the module, defines the security contract, writes the request handler
- **Crypto Agent (@crypto-agent)** — implements the actual hashing and token verification

**The Lead Agent writes the program.** It must:

1. Define a `def-interface AuthSystem` with two methods:
   - `hash-password`: takes a raw password string, returns a hashed string
   - `verify-token`: takes a token string, returns a boolean

2. Write a `login-handler` function that:
   - Accepts a username (string) and a raw password (string)
   - Delegates password hashing to `@crypto-agent` via `?delegate`
   - If the crypto agent fails, falls back to returning an error message using `on-failure`
   - Returns a `Result[string, string]` — either the hashed password on success, or an error message

3. Write a `validate-session` function that:
   - Accepts a session token string
   - Delegates token verification to `@crypto-agent` via `?delegate`
   - If the crypto agent is unavailable, defaults to rejecting the token (returns `false`)
   - Returns a boolean

4. Include `check` blocks:
   - A valid delegation result (simulated via `on-failure` fallback) always produces a `Result`
   - The fallback for `validate-session` always returns `false` (fail-closed)

5. Include a `pre` contract on `login-handler`: the password must not be empty
