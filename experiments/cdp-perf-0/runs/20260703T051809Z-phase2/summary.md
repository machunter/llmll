# cdp-perf-0 Phase 2 run summary

- **Timestamp (UTC):** 20260703T051809Z
- **Compiler:** `llmll 0.14.5`
- **Primary reps:** 15 measured + 2 warmup
- **Secondary reps:** 5 measured + 1 warmup

## Primary corpus (re-measured at higher reps)

| fixture | bare (ms) | cdp (ms) | overhead (ms) | candidates | ms/candidate | tag |
|---|---|---|---|---|---|---|
| b1 | 399.1 | 683.2 | 284.2 | 6 | 47.4 | match-or-hole |
| b3 | 384.8 | 584.2 | 199.4 | 4 | 49.8 | match-or-hole |
| b5 | 407.3 | 660.8 | 253.5 | 5 | 50.7 | match-or-hole |
| totp | 435.5 | 459.7 | 24.2 | 0 | n/a | plain |
| erc20 | 429.9 | 1105.9 | 675.9 | 15 | 45.1 | plain |
| banking | 490.5 | 999.7 | 509.2 | 11 | 46.3 | plain |

## Secondary corpus

| fixture | status | overhead (ms) | candidates | ms/candidate | tag |
|---|---|---|---|---|---|
| sec_examples_effect-authority_bounded_llmll | ok | -43.6 | 0 | n/a | plain |
| sec_examples_effect-authority_unbounded_llmll | ok | -52.9 | 0 | n/a | match-or-hole |
| sec_examples_event_log_test_event_log_test_llmll | ok | 10.3 | 0 | n/a | plain |
| sec_examples_hangman_sexp_hangman_llmll | ok | 8.4 | 0 | n/a | match-or-hole |
| sec_examples_life_sexp_core_llmll | ok | 33.8 | 0 | n/a | plain |
| sec_examples_life_sexp_main_llmll | ok | 9.2 | 0 | n/a | match-or-hole |
| sec_examples_life_sexp_world_llmll | ok | -4.8 | 0 | n/a | plain |
| sec_examples_nested-result_safe-withdraw-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_nested-result_safe-withdraw_llmll | ok | 66.2 | 0 | n/a | match-or-hole |
| sec_examples_niw-measure_word-pad-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_niw-measure_word-pad_llmll | ok | 149.6 | 4 | 37.4 | plain |
| sec_examples_outcome-totality_classify-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_outcome-totality_classify_llmll | ok | -4.0 | 0 | n/a | plain |
| sec_examples_pair_type_test_pair_destruct_let_llmll | ok | -5.8 | 0 | n/a | match-or-hole |
| sec_examples_pair_type_test_pair_destruct_nested_llmll | ok | 10.4 | 0 | n/a | plain |
| sec_examples_pair_type_test_pair_type_test_llmll | ok | 10.3 | 0 | n/a | plain |
| sec_examples_pair_type_test_string_concat_sugar_llmll | ok | -23.6 | 0 | n/a | plain |
| sec_examples_payments-core_conserve-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_conserve_llmll | ok | 3.4 | 0 | n/a | plain |
| sec_examples_payments-core_settle-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_settle_llmll | ok | -3.5 | 0 | n/a | match-or-hole |
| sec_examples_payments-core_transfer-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_transfer-unsafe_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_transfer_llmll | ok | 201.9 | 6 | 33.6 | plain |
| sec_examples_refined-payload_refined-payload-bad-elim_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_refined-payload_refined-payload-bad-forward_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_refined-payload_refined-payload_llmll | ok | 142.5 | 4 | 35.6 | match-or-hole |
| sec_examples_session-pay_open-and-pay-bad-step_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_session-pay_open-and-pay-unbounded_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_session-pay_open-and-pay-unsafe_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_session-pay_open-and-pay_llmll | ok | -230.3 | 6 | -38.4 | plain |
| sec_examples_tcp_rfc793_step-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_tcp_rfc793_step-weak_llmll | ok | 194.1 | 0 | n/a | plain |
| sec_examples_tcp_rfc793_step_llmll | ok | 418.2 | 0 | n/a | plain |
| sec_examples_tictactoe_sexp_tictactoe_llmll | ok | -1.9 | 0 | n/a | match-or-hole |
| sec_examples_withdraw-demo_audit_llmll | ok | -74.3 | 0 | n/a | plain |
| sec_examples_withdraw-demo_compose-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_withdraw-demo_compose_llmll | ok | 188.3 | 6 | 31.4 | plain |
| sec_examples_withdraw-demo_demo_llmll | ok | 582.8 | 17 | 34.3 | match-or-hole |
| sec_examples_withdraw-demo_return-refine-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_withdraw-demo_return-refine_llmll | ok | 26.9 | 1 | 26.9 | plain |
| sec_examples_withdraw-demo_withdraw-outcome-bad_llmll | ERROR/n/a | - | - | - | - |
| sec_examples_withdraw-demo_withdraw_llmll | ok | 121.5 | 6 | 20.3 | match-or-hole |
| sec_examples_withdraw_llmll | ok | 274.4 | 6 | 45.7 | plain |
| sec_examples_auth_module_auth_module_ast_json | ok | -16.3 | 0 | n/a | match-or-hole |
| sec_examples_conways_life_json_verifier_life_ast_json | ok | 1084.3 | 6 | 180.7 | match-or-hole |
| sec_examples_effect-authority_bounded_ast_json | ok | -24.9 | 0 | n/a | plain |
| sec_examples_effect-authority_unbounded_ast_json | ok | -22.4 | 0 | n/a | plain |
| sec_examples_erc20_token_erc20_ast_json | ok | 564.8 | 15 | 37.7 | match-or-hole |
| sec_examples_hangman_json_hangman_ast_json | ok | 0.9 | 0 | n/a | match-or-hole |
| sec_examples_hangman_json_verifier_hangman_ast_json | ok | 38.9 | 0 | n/a | match-or-hole |
| sec_examples_life_json_core_ast_json | ok | -8.7 | 0 | n/a | plain |
| sec_examples_life_json_main_ast_json | ok | -63.6 | 0 | n/a | match-or-hole |
| sec_examples_life_json_world_ast_json | ok | -10.2 | 0 | n/a | plain |
| sec_examples_nested-result_safe-withdraw-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_nested-result_safe-withdraw_ast_json | ok | -23.3 | 0 | n/a | match-or-hole |
| sec_examples_niw-measure_word-pad-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_niw-measure_word-pad_ast_json | ok | 306.1 | 4 | 76.5 | plain |
| sec_examples_orchestrator_walkthrough_auth_module_ast_json | ok | 23.6 | 0 | n/a | match-or-hole |
| sec_examples_orchestrator_walkthrough_auth_module_filled_ast_json | ok | 50.7 | 0 | n/a | match-or-hole |
| sec_examples_outcome-totality_classify-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_outcome-totality_classify_ast_json | ok | -27.4 | 0 | n/a | plain |
| sec_examples_pair_type_test_do_emit_ac_ast_json | ok | 45.4 | 0 | n/a | plain |
| sec_examples_pair_type_test_pair_destruct_let_ast_json | ok | -28.5 | 0 | n/a | plain |
| sec_examples_pair_type_test_pair_match_ac4_ast_json | ok | -118.3 | 0 | n/a | plain |
| sec_examples_pair_type_test_pair_type_test_ast_json | ok | 92.7 | 0 | n/a | plain |
| sec_examples_payments-core_conserve-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_conserve_ast_json | ok | -60.0 | 0 | n/a | plain |
| sec_examples_payments-core_settle-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_settle_ast_json | ok | 25.2 | 0 | n/a | match-or-hole |
| sec_examples_payments-core_transfer-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_transfer-unsafe_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_payments-core_transfer_ast_json | ok | 404.2 | 6 | 67.4 | plain |
| sec_examples_refined-payload_refined-payload-bad-elim_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_refined-payload_refined-payload-bad-forward_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_refined-payload_refined-payload_ast_json | ok | 239.5 | 4 | 59.9 | match-or-hole |
| sec_examples_session-pay_open-and-pay-bad-step_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_session-pay_open-and-pay-unbounded_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_session-pay_open-and-pay-unsafe_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_session-pay_open-and-pay_ast_json | ok | -1167.1 | 6 | -194.5 | plain |
| sec_examples_tcp_rfc793_step-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_tcp_rfc793_step-weak_ast_json | ok | 83.8 | 0 | n/a | plain |
| sec_examples_tcp_rfc793_step_ast_json | ok | -293.5 | 0 | n/a | plain |
| sec_examples_tictactoe_json_tictactoe_ast_json | ok | 19.6 | 0 | n/a | match-or-hole |
| sec_examples_tictactoe_json_verifier_tictactoe_ast_json | ok | -106.7 | 0 | n/a | match-or-hole |
| sec_examples_totp_rfc6238_totp_ast_json | ok | 743.9 | 14 | 53.1 | match-or-hole |
| sec_examples_withdraw-demo_audit_ast_json | ok | 0.8 | 0 | n/a | plain |
| sec_examples_withdraw-demo_demo_ast_json | ok | 889.7 | 17 | 52.3 | plain |
| sec_examples_withdraw-demo_return-refine_ast_json | ok | 11.4 | 1 | 11.4 | plain |
| sec_examples_withdraw-demo_withdraw-outcome-bad_ast_json | ERROR/n/a | - | - | - | - |
| sec_examples_withdraw-demo_withdraw_ast_json | ok | 451.2 | 6 | 75.2 | plain |

## Fit across all valid fixtures (candidate_count > 0)

- n = 24
- a = -51.62 ms, b = 46.29 ms/candidate, R² = 0.2638

## Per-candidate cost by structural tag (crude substring heuristic)

- `match-or-hole`: n=10, median ms/candidate = 48.6
- `plain`: n=14, median ms/candidate = 41.2
