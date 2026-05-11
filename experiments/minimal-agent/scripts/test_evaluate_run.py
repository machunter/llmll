"""Unit tests for the minimal-agent harness evaluator (EL-A).

Covers the three EL-A changes per
`experiments/minimal-agent/findings/experiment-lead.md`:

- E1: call-graph delegation classification (collect_checks +
  build_function_table + body_reaches_delegation_via_calls + extract_callee_names)
- E2: three-signal Result feature split (walk_json_ast + scan_json_ast_features)
- E3: contract expectation flip on experiment 001 login-handler.pre.proof_required
  (validated indirectly via quality_grade behaviour)

Run via:
    python3 -m unittest experiments/minimal-agent/scripts/test_evaluate_run.py
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

# Ensure the scripts directory is on sys.path so we can import the evaluator.
SCRIPTS_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPTS_DIR))

import evaluate_run  # noqa: E402


# ---------------------------------------------------------------------------
# AST builders — synthetic JSON-AST fragments mimicking the schema.
# ---------------------------------------------------------------------------


def app(fn: str, *args):
    return {"kind": "app", "fn": fn, "args": list(args)}


def var(name: str):
    return {"kind": "var", "name": name}


def lit_int(value: int):
    return {"kind": "lit-int", "value": value}


def lit_string(value: str):
    return {"kind": "lit-string", "value": value}


def lit_bool(value: bool):
    return {"kind": "lit-bool", "value": value}


def hole_delegate(agent: str = "@a", desc: str = "x", return_type=None):
    return {
        "kind": "hole-delegate",
        "agent": agent,
        "description": desc,
        "return_type": return_type or {"kind": "primitive", "name": "int"},
    }


def result_type(t, e):
    return {"kind": "result", "ok": t, "err": e}


def pattern_constructor(name: str, *sub_patterns):
    return {"kind": "constructor", "constructor": name, "sub_patterns": list(sub_patterns)}


def pattern_var(name: str):
    return {"kind": "var", "name": name}


def match_(scrutinee, arms):
    return {"kind": "match", "scrutinee": scrutinee, "arms": arms}


def def_logic(name: str, body, params=None, return_type=None):
    out = {"kind": "def-logic", "name": name, "params": params or [], "body": body}
    if return_type is not None:
        out["return_type"] = return_type
    return out


def check(label: str, body, bindings=None):
    return {
        "kind": "check",
        "label": label,
        "for_all": {"bindings": bindings or [], "body": body},
    }


def program(*statements):
    return {"schemaVersion": "0.4.0", "statements": list(statements)}


# ---------------------------------------------------------------------------
# E1: call-graph delegation
# ---------------------------------------------------------------------------


class BuildFunctionTableTests(unittest.TestCase):
    def test_def_logic_only(self):
        ast = program(
            def_logic("foo", lit_int(1)),
            def_logic("bar", app("foo")),
        )
        table = evaluate_run.build_function_table(ast)
        self.assertEqual(set(table.keys()), {"foo", "bar"})
        self.assertEqual(table["foo"], lit_int(1))

    def test_mixed_kinds_only_def_logic(self):
        ast = program(
            def_logic("foo", lit_int(1)),
            {"kind": "def-interface", "name": "Iface", "methods": []},
            {"kind": "def-main", "step": var("x")},
        )
        table = evaluate_run.build_function_table(ast)
        self.assertEqual(set(table.keys()), {"foo"})

    def test_none_ast_returns_empty(self):
        self.assertEqual(evaluate_run.build_function_table(None), {})
        self.assertEqual(evaluate_run.build_function_table({}), {})


class ExtractCalleeNamesTests(unittest.TestCase):
    def test_direct_call(self):
        body = app("foo", lit_int(1))
        self.assertEqual(evaluate_run.extract_callee_names(body), {"foo"})

    def test_nested_calls_in_if(self):
        body = {
            "kind": "if",
            "cond": app("is-positive", var("x")),
            "then": app("foo", var("x")),
            "else": app("bar", var("x")),
        }
        self.assertEqual(
            evaluate_run.extract_callee_names(body), {"is-positive", "foo", "bar"}
        )

    def test_skips_qual_app(self):
        body = {"kind": "qual-app", "qual_fn": "wasi.io.stdout", "args": []}
        self.assertEqual(evaluate_run.extract_callee_names(body), set())


class BodyReachesDelegationTests(unittest.TestCase):
    def test_direct_delegate_in_callee(self):
        table = {"hash": hole_delegate()}
        body = app("hash", lit_string("pw"))
        self.assertTrue(
            evaluate_run.body_reaches_delegation_via_calls(body, table)
        )

    def test_transitive_through_two_hops(self):
        table = {
            "outer": app("inner"),
            "inner": hole_delegate(),
        }
        body = app("outer")
        self.assertTrue(
            evaluate_run.body_reaches_delegation_via_calls(body, table)
        )

    def test_no_delegation_returns_false(self):
        table = {"foo": lit_int(1), "bar": app("foo")}
        body = app("bar")
        self.assertFalse(
            evaluate_run.body_reaches_delegation_via_calls(body, table)
        )

    def test_mutual_recursion_is_cycle_safe(self):
        # f calls g; g calls f. No delegation anywhere. Must not recurse forever.
        table = {"f": app("g"), "g": app("f")}
        body = app("f")
        self.assertFalse(
            evaluate_run.body_reaches_delegation_via_calls(body, table)
        )

    def test_builtin_callee_not_in_table_skips(self):
        # Unknown function name: skipped. The label-regex fallback in
        # collect_checks would catch this if it matters.
        table: dict = {}
        body = app("some-builtin")
        self.assertFalse(
            evaluate_run.body_reaches_delegation_via_calls(body, table)
        )


class CollectChecksTests(unittest.TestCase):
    def test_call_graph_signal(self):
        ast = program(
            def_logic("login", hole_delegate()),
            check("login-result-valid", app("login")),
        )
        result = evaluate_run.collect_checks(ast)
        self.assertEqual(len(result), 1)
        self.assertTrue(result[0]["delegation_dependent"])
        self.assertIn("call graph reaches delegation", result[0]["reasons"])

    def test_label_only_signal(self):
        # No delegation in check body and no transitive callee with delegation;
        # but label has "delegation" keyword. Label fallback should fire.
        ast = program(
            def_logic("foo", lit_int(1)),
            check("delegation-keyword-only", app("foo")),
        )
        result = evaluate_run.collect_checks(ast)
        self.assertTrue(result[0]["delegation_dependent"])
        self.assertEqual(result[0]["reasons"], ["delegation-related label"])

    def test_inline_delegate_in_check_body(self):
        ast = program(
            check("inline-delegate", hole_delegate()),
        )
        result = evaluate_run.collect_checks(ast)
        self.assertTrue(result[0]["delegation_dependent"])
        self.assertIn("contains delegation or await", result[0]["reasons"])

    def test_no_signals_neutral_check(self):
        ast = program(
            def_logic("foo", lit_int(1)),
            check("addition-commutes", app("foo")),
        )
        result = evaluate_run.collect_checks(ast)
        self.assertFalse(result[0]["delegation_dependent"])
        self.assertEqual(result[0]["reasons"], [])


# ---------------------------------------------------------------------------
# E2: three-signal Result feature scan
# ---------------------------------------------------------------------------


class WalkJsonAstResultSignalsTests(unittest.TestCase):
    def _scan(self, ast) -> dict[str, bool]:
        return evaluate_run.scan_json_ast_features(json.dumps(ast))

    def test_result_type_only(self):
        ast = program(def_logic("f", lit_int(1), return_type=result_type(
            {"kind": "primitive", "name": "int"},
            {"kind": "primitive", "name": "string"},
        )))
        found = self._scan(ast)
        self.assertTrue(found["Result-type"])
        self.assertFalse(found["Result-helpers"])
        self.assertFalse(found["Result-pattern"])
        self.assertEqual(found["Result"], found["Result-type"])

    def test_result_pattern_only(self):
        # Match arms use pattern-constructor (kind: "constructor"). No Result-type.
        body = match_(
            var("x"),
            [
                {"pattern": pattern_constructor("Success", pattern_var("v")), "body": var("v")},
                {"pattern": pattern_constructor("Error", pattern_var("e")), "body": lit_int(0)},
            ],
        )
        ast = program(def_logic("f", body))
        found = self._scan(ast)
        self.assertFalse(found["Result-type"])
        self.assertTrue(found["Result-pattern"])
        self.assertFalse(found["Result-helpers"])

    def test_result_helpers_only(self):
        # ExprApp with fn = ok/err/is-ok — helper invocation, not type position.
        body = app("ok", lit_int(5))
        ast = program(def_logic("f", body))
        found = self._scan(ast)
        self.assertFalse(found["Result-type"])
        self.assertTrue(found["Result-helpers"])
        self.assertFalse(found["Result-pattern"])

    def test_all_three_signals_together(self):
        body = match_(
            app("ok", lit_int(5)),
            [
                {"pattern": pattern_constructor("Success", pattern_var("v")), "body": var("v")},
            ],
        )
        ast = program(
            def_logic(
                "f", body,
                return_type=result_type(
                    {"kind": "primitive", "name": "int"},
                    {"kind": "primitive", "name": "string"},
                ),
            )
        )
        found = self._scan(ast)
        self.assertTrue(found["Result-type"])
        self.assertTrue(found["Result-helpers"])
        self.assertTrue(found["Result-pattern"])

    def test_unrelated_constructor_does_not_fire_result_pattern(self):
        # A pattern with a constructor not in {Success, Error} (e.g., Cons)
        # must not flip Result-pattern.
        body = match_(
            var("xs"),
            [
                {"pattern": pattern_constructor("Cons", pattern_var("h"), pattern_var("t")), "body": var("h")},
            ],
        )
        ast = program(def_logic("f", body))
        found = self._scan(ast)
        self.assertFalse(found["Result-pattern"])

    def test_unrelated_fn_does_not_fire_result_helpers(self):
        # An app to a non-helper fn (e.g., "+") must not flip Result-helpers.
        body = app("+", lit_int(1), lit_int(2))
        ast = program(def_logic("f", body))
        found = self._scan(ast)
        self.assertFalse(found["Result-helpers"])


class ScanFeaturesMissingRequiredTests(unittest.TestCase):
    def test_result_type_drives_missing_required(self):
        # Solution uses Result-helpers and Result-pattern but no Result-type.
        # missing_required must list Result-type.
        body = match_(
            app("err", lit_string("e")),
            [
                {"pattern": pattern_constructor("Error", pattern_var("x")), "body": lit_int(0)},
            ],
        )
        ast = program(def_logic("f", body))
        found = evaluate_run.scan_json_ast_features(json.dumps(ast))
        # Sanity: helpers + pattern fired but type did not.
        self.assertFalse(found["Result-type"])
        self.assertTrue(found["Result-helpers"])
        self.assertTrue(found["Result-pattern"])
        # Required is checked against found via the keys in REQUIRED_FEATURES;
        # since experiment 001 requires "Result-type" (not just "Result"),
        # the missing-required check elsewhere would flag this.
        required = evaluate_run.REQUIRED_FEATURES[1]
        self.assertIn("Result-type", required)
        missing = [r for r in required if not found.get(r, False)]
        self.assertIn("Result-type", missing)

    def test_back_compat_result_field_derives_from_result_type(self):
        ast = program(def_logic("f", lit_int(1), return_type=result_type(
            {"kind": "primitive", "name": "int"},
            {"kind": "primitive", "name": "string"},
        )))
        found = evaluate_run.scan_json_ast_features(json.dumps(ast))
        self.assertEqual(found["Result"], found["Result-type"])
        self.assertTrue(found["Result"])


# ---------------------------------------------------------------------------
# E3: contract expectation flip
# ---------------------------------------------------------------------------


class ContractExpectationE3Tests(unittest.TestCase):
    def test_experiment_001_login_handler_pre_proof_required_is_false(self):
        # E3-revert (post-EL-A re-validation, batch 20260510T235111Z):
        # The original EL-A E3 change flipped this to True to lift the B
        # ceiling, but in production all 9 top-tier attempts dropped B→C
        # because top-tier agents (correctly) do not emit ?proof-required
        # on the pre clause — `(password not empty)` is QF-LIA-tractable
        # and ?proof-required is scoped to postconditions the verifier
        # cannot discharge (LLMLL.md §13.8 / §5.3.5).
        # Regression guard: keep this at False until experiment 001 is
        # restructured to encapsulate the delegate in an uncontracted
        # helper (Option 2 of the E3 finding, deferred).
        expectations = evaluate_run.CONTRACT_EXPECTATIONS
        self.assertIn(1, expectations)
        self.assertIn("login-handler", expectations[1])
        self.assertIn("pre", expectations[1]["login-handler"])
        self.assertFalse(
            expectations[1]["login-handler"]["pre"]["proof_required"],
            "E3-revert regression: login-handler.pre.proof_required must "
            "remain False. Flipping to True over-restricts the experiment "
            "because the pre clause is QF-LIA-tractable and does not need "
            "a ?proof-required marker. See postmortem-001-el-a-revalidation "
            "F-201 for the empirical evidence.",
        )


class FeaturePresentAndLabelTests(unittest.TestCase):
    def test_string_spec_present_when_true(self):
        self.assertTrue(evaluate_run.feature_present("Result-type", {"Result-type": True}))

    def test_string_spec_absent_when_false_or_missing(self):
        self.assertFalse(evaluate_run.feature_present("Result-type", {"Result-type": False}))
        self.assertFalse(evaluate_run.feature_present("Result-type", {}))

    def test_disjunction_satisfied_by_either_alternative(self):
        # F-301 loosening: ["Result-type", "Result-pattern"] is satisfied if
        # either name is True in found.
        self.assertTrue(
            evaluate_run.feature_present(
                ["Result-type", "Result-pattern"],
                {"Result-type": False, "Result-pattern": True},
            )
        )
        self.assertTrue(
            evaluate_run.feature_present(
                ["Result-type", "Result-pattern"],
                {"Result-type": True, "Result-pattern": False},
            )
        )

    def test_disjunction_unsatisfied_when_all_alternatives_false(self):
        self.assertFalse(
            evaluate_run.feature_present(
                ["Result-type", "Result-pattern"],
                {"Result-type": False, "Result-pattern": False},
            )
        )

    def test_feature_label_string_passthrough(self):
        self.assertEqual(evaluate_run.feature_label("Result-type"), "Result-type")

    def test_feature_label_disjunction_joins_with_pipe(self):
        self.assertEqual(
            evaluate_run.feature_label(["Result-type", "Result-pattern"]),
            "Result-type | Result-pattern",
        )


class RequiredFeaturesShapeTests(unittest.TestCase):
    """Regression guards for the F-301 002/003 loosening — Promise dropped from
    REQUIRED_FEATURES[2]; Result-type|Result-pattern disjunction in 002 and 003.
    """

    def test_001_requires_explicit_result_type(self):
        # Experiment 001 still requires explicit Result-type — the spec
        # mandates `Result[string, string]` as login-handler's return type
        # (001-two-agent-auth.md:23). Don't accidentally apply the
        # disjunction loosening to 001.
        self.assertIn("Result-type", evaluate_run.REQUIRED_FEATURES[1])

    def test_002_promise_removed(self):
        # F-301: Promise is inferred from ?delegate-async per LLMLL.md §11.2
        # and should not be in the required list.
        self.assertNotIn("Promise", evaluate_run.REQUIRED_FEATURES[2])

    def test_002_result_uses_disjunction(self):
        # F-301: Result-type | Result-pattern disjunction.
        self.assertIn(
            ["Result-type", "Result-pattern"],
            evaluate_run.REQUIRED_FEATURES[2],
        )

    def test_003_result_uses_disjunction(self):
        # Same loosening applied to 003 for consistency (003 also uses
        # ?delegate-async + await, same inferred-annotation pattern).
        self.assertIn(
            ["Result-type", "Result-pattern"],
            evaluate_run.REQUIRED_FEATURES[3],
        )


class QualityGradeTests(unittest.TestCase):
    def _grade(self, **kwargs) -> str:
        # Minimal report shape sufficient for quality_grade().
        report = {
            "status": "passed",
            "first_error": None,
            "feature_scan": {"missing_required": []},
            **kwargs,
        }
        return evaluate_run.quality_grade(report)

    def test_missing_required_returns_f(self):
        grade = self._grade(
            feature_scan={"missing_required": ["Result-type"]},
        )
        self.assertEqual(grade, "F")

    def test_all_passed_proof_required_ceiling_accepted_returns_a(self):
        # E3 path: when proof_required ceiling is accepted (agent emitted
        # ?proof-required for an expected proof-required clause), A is reachable.
        grade = self._grade(
            test_assessment={
                "effective_total": 2,
                "effective_passed": 2,
                "all_applicable_passed": True,
                "excluded_delegation_dependent": 0,
            },
            contract_assessment={
                "all_required_contracts_met": True,
                "asserted_without_proof": 0,
                "proof_required_ceiling_accepted": 1,
            },
        )
        self.assertEqual(grade, "A")

    def test_asserted_without_proof_returns_b(self):
        # E3 path: when agent did not emit ?proof-required for an expected
        # proof-required clause, contract is asserted_without_proof → grade B.
        grade = self._grade(
            test_assessment={
                "effective_total": 2,
                "effective_passed": 2,
                "all_applicable_passed": True,
                "excluded_delegation_dependent": 0,
            },
            contract_assessment={
                "all_required_contracts_met": True,
                "asserted_without_proof": 1,
                "proof_required_ceiling_accepted": 0,
            },
        )
        self.assertEqual(grade, "B")

    def test_all_tests_excluded_as_delegation_dependent_returns_b(self):
        # Edge: zero effective tests but excluded > 0 → grade B (delegation-only
        # solution, no testable surface).
        grade = self._grade(
            test_assessment={
                "effective_total": 0,
                "effective_passed": 0,
                "all_applicable_passed": True,
                "excluded_delegation_dependent": 2,
            },
            contract_assessment={
                "all_required_contracts_met": True,
                "asserted_without_proof": 0,
                "proof_required_ceiling_accepted": 0,
            },
        )
        self.assertEqual(grade, "B")


if __name__ == "__main__":
    unittest.main()
