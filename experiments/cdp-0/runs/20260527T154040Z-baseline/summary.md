# CDP-0 baseline run summary

- **Timestamp (UTC):** 20260527T154040Z
- **Compiler SHA:** `121815a` (lt-cdp/discriminative-power-axis)
- **`llmll version`:** `llmll 0.10.8`
- **CDP scope:** `CDPScopeAllDefLogic`
- **Adjudication:** `cdp-discriminating-weak`

## Aggregate

- Contracted functions across corpus: **26**
- Defined-score functions: **11** (42.3%)
- Midrange (0 < DP < 1) functions: **4** (36.4% of defined)

### Score distribution (defined scores only)

- mean: **0.416**, median: **0.644**
- min: 0.000, p10: 0.000, p50: 0.644, p90: 1.000, max: 1.000

### Warning counts

- `const-satisfies-post`: 11
- `identity-satisfies-post`: 8
- `not-requested`: 11
- `vacuous-over-omega`: 4

### spec-entropy annotation counts

- `strict`: 26

## Primary corpus results

- **b1** (examples/benchmarks/b1-withdraw.llmll): 1 contracted fn(s)
- **b3** (examples/benchmarks/b3-safe-first.llmll): 1 contracted fn(s)
- **b5** (examples/benchmarks/b5-double.llmll): 1 contracted fn(s)
- **totp** (examples/totp_rfc6238/totp_filled.ast.json): 5 contracted fn(s)
- **erc20** (examples/erc20_token/erc20_filled.ast.json): 6 contracted fn(s)
- **banking** (examples/banking_ledger/banking.llmll): 6 contracted fn(s)

## Secondary corpus results

- **sec_examples_event_log_test_event_log_test_llmll** (examples/event_log_test/event_log_test.llmll): 0 contracted fn(s)
- **sec_examples_hangman_sexp_hangman_llmll** (examples/hangman_sexp/hangman.llmll): 0 contracted fn(s)
- **sec_examples_life_sexp_core_llmll** (examples/life_sexp/core.llmll): 0 contracted fn(s)
- **sec_examples_life_sexp_main_llmll** (examples/life_sexp/main.llmll): 0 contracted fn(s)
- **sec_examples_life_sexp_world_llmll** (examples/life_sexp/world.llmll): 0 contracted fn(s)
- **sec_examples_pair_type_test_pair_destruct_let_llmll** (examples/pair_type_test/pair_destruct_let.llmll): 0 contracted fn(s)
- **sec_examples_pair_type_test_pair_destruct_nested_llmll** (examples/pair_type_test/pair_destruct_nested.llmll): 0 contracted fn(s)
- **sec_examples_pair_type_test_pair_type_test_llmll** (examples/pair_type_test/pair_type_test.llmll): 0 contracted fn(s)
- **sec_examples_pair_type_test_string_concat_sugar_llmll** (examples/pair_type_test/string_concat_sugar.llmll): 0 contracted fn(s)
- **sec_examples_tictactoe_sexp_tictactoe_llmll** (examples/tictactoe_sexp/tictactoe.llmll): 0 contracted fn(s)
- **sec_examples_withdraw-demo_withdraw_llmll** (examples/withdraw-demo/withdraw.llmll): 1 contracted fn(s)
- **sec_examples_withdraw_llmll** (examples/withdraw.llmll): 1 contracted fn(s)
- **sec_examples_auth_module_auth_module_ast_json** (examples/auth_module/auth_module.ast.json): 1 contracted fn(s)
- **sec_examples_conways_life_json_verifier_life_ast_json** (examples/conways_life_json_verifier/life.ast.json): EXCLUDED — error: type mismatch in 'first': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
warning: :done? should return bool; found non-bool type (ignored in v0.2)

- **sec_examples_erc20_token_erc20_ast_json** (examples/erc20_token/erc20.ast.json): 6 contracted fn(s)
- **sec_examples_hangman_json_hangman_ast_json** (examples/hangman_json/hangman.ast.json): 0 contracted fn(s)
- **sec_examples_hangman_json_verifier_hangman_ast_json** (examples/hangman_json_verifier/hangman.ast.json): EXCLUDED — error: infinite type: a occurs in list[a]
error: type mismatch in 'first': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
warning: :done? should return bool; found non-bool type (ignored in v0.2)

- **sec_examples_life_json_core_ast_json** (examples/life_json/core.ast.json): 0 contracted fn(s)
- **sec_examples_life_json_main_ast_json** (examples/life_json/main.ast.json): EXCLUDED — error: call to unknown function 'glider-grid'
error: call to unknown function 'make-world'
error: call to unknown function 'render-world'
error: call to unknown function 'evolve'
error: call to unknown function 'render-world'
warning: :done? should return bool; found non-bool type (ignored in v0.2)

- **sec_examples_life_json_world_ast_json** (examples/life_json/world.ast.json): EXCLUDED — error: call to unknown function 'next-cell-state'

- **sec_examples_orchestrator_walkthrough_auth_module_ast_json** (examples/orchestrator_walkthrough/auth_module.ast.json): 1 contracted fn(s)
- **sec_examples_orchestrator_walkthrough_auth_module_filled_ast_json** (examples/orchestrator_walkthrough/auth_module_filled.ast.json): 1 contracted fn(s)
- **sec_examples_pair_type_test_do_emit_ac_ast_json** (examples/pair_type_test/do_emit_ac.ast.json): EXCLUDED — error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability ...))
warning: do-block step 0: current codegen discards this intermediate command. Use `seq-commands` to sequence IO actions explicitly.
error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability 
- **sec_examples_pair_type_test_pair_destruct_let_ast_json** (examples/pair_type_test/pair_destruct_let.ast.json): 0 contracted fn(s)
- **sec_examples_pair_type_test_pair_match_ac4_ast_json** (examples/pair_type_test/pair_match_ac4.ast.json): EXCLUDED — error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability ...))

- **sec_examples_pair_type_test_pair_type_test_ast_json** (examples/pair_type_test/pair_type_test.ast.json): EXCLUDED — error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability ...))

- **sec_examples_tictactoe_json_tictactoe_ast_json** (examples/tictactoe_json/tictactoe.ast.json): 0 contracted fn(s)
- **sec_examples_tictactoe_json_verifier_tictactoe_ast_json** (examples/tictactoe_json_verifier/tictactoe.ast.json): EXCLUDED — error: type mismatch in 'first': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: if branches have different types: (unit, Command) vs ((?, (?, ?)), Command)
warning: :done? should return bool; found non-bool type (ignored in v0.2)

- **sec_examples_totp_rfc6238_totp_ast_json** (examples/totp_rfc6238/totp.ast.json): 5 contracted fn(s)
- **sec_examples_withdraw-demo_withdraw_ast_json** (examples/withdraw-demo/withdraw.ast.json): 1 contracted fn(s)

## Excluded fixtures (verify-failure)

- **sec_examples_conways_life_json_verifier_life_ast_json** (examples/conways_life_json_verifier/life.ast.json): error: type mismatch in 'first': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
warning: :done? should return bool; found non-bool type (ignored in v0.2)

- **sec_examples_hangman_json_verifier_hangman_ast_json** (examples/hangman_json_verifier/hangman.ast.json): error: infinite type: a occurs in list[a]
error: type mismatch in 'first': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
warning: :done? should return bool; found non-bool type (ignored in v0.2)

- **sec_examples_life_json_main_ast_json** (examples/life_json/main.ast.json): error: call to unknown function 'glider-grid'
error: call to unknown function 'make-world'
error: call to unknown function 'render-world'
error: call to unknown function 'evolve'
error: call to unknown function 'render-world'
warning: :done? should return bool; found non-bool type (ignored in v0.2)

- **sec_examples_life_json_world_ast_json** (examples/life_json/world.ast.json): error: call to unknown function 'next-cell-state'

- **sec_examples_pair_type_test_do_emit_ac_ast_json** (examples/pair_type_test/do_emit_ac.ast.json): error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability ...))
warning: do-block step 0: current codegen discards this intermediate command. Use `seq-commands` to sequence IO actions explicitly.
error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability 
- **sec_examples_pair_type_test_pair_match_ac4_ast_json** (examples/pair_type_test/pair_match_ac4.ast.json): error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability ...))

- **sec_examples_pair_type_test_pair_type_test_ast_json** (examples/pair_type_test/pair_type_test.ast.json): error: wasi.io.stdout requires (import wasi.io (capability ...)) — wasi.* functions need an explicit capability import in each module
  suggestion: Add: (import wasi.io (capability ...))

- **sec_examples_tictactoe_json_verifier_tictactoe_ast_json** (examples/tictactoe_json_verifier/tictactoe.ast.json): error: type mismatch in 'first': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: type mismatch in 'second': expected (a, b), got unit
error: if branches have different types: (unit, Command) vs ((?, (?, ?)), Command)
warning: :done? should return bool; found non-bool type (ignored in v0.2)

