"""
test_lead_agent.py — Tests for Lead Agent and quality heuristics.

v0.4: Sprint 2 Tasks 4-6.
"""

from __future__ import annotations

import json
import pytest

from llmll_orchestra.quality import check_plan_quality, QualityResult
from llmll_orchestra.lead_agent import (
    LeadAgent, _plan_to_source, _sexpr_string, _parse_json_response,
)
from llmll_orchestra.agent import DryRunAgent
from llmll_orchestra.compiler import Compiler


# ─────────────────────────────────────────────────────────────────────
# Quality heuristics
# ─────────────────────────────────────────────────────────────────────

class TestQualityHeuristics:

    def test_all_string_types_blocks(self):
        """Plans with all-string types are rejected."""
        plan = {
            "modules": [{
                "name": "auth",
                "functions": [
                    {"name": "login", "params": [{"name": "u", "type": "string"}, {"name": "p", "type": "string"}], "returns": "string", "agent": "@verifier"},
                    {"name": "logout", "params": [{"name": "t", "type": "string"}], "returns": "string", "agent": "@verifier"},
                ],
            }]
        }
        results = check_plan_quality(plan)
        blocking = [r for r in results if r.blocking]
        assert any(r.heuristic == "all-string-types" for r in blocking)

    def test_mixed_types_passes(self):
        """Plans with mixed types are not blocked for all-string."""
        plan = {
            "modules": [{
                "name": "auth",
                "functions": [
                    {"name": "login", "params": [{"name": "u", "type": "string"}, {"name": "p", "type": "string"}], "returns": "Result[string, string]", "agent": "@verifier"},
                ],
            }]
        }
        results = check_plan_quality(plan)
        blocking = [r for r in results if r.blocking and r.heuristic == "all-string-types"]
        assert len(blocking) == 0

    def test_unassigned_agents_blocks(self):
        """Plans with unassigned agents are rejected."""
        plan = {
            "modules": [{
                "name": "core",
                "functions": [
                    {"name": "process", "params": [], "returns": "int", "agent": ""},
                    {"name": "compute", "params": [], "returns": "int"},
                ],
            }]
        }
        results = check_plan_quality(plan)
        blocking = [r for r in results if r.blocking]
        assert any(r.heuristic == "unassigned-agents" for r in blocking)

    def test_all_agents_assigned_passes(self):
        """Plans with all agents assigned pass the check."""
        plan = {
            "modules": [{
                "name": "core",
                "functions": [
                    {"name": "process", "params": [{"name": "x", "type": "int"}], "returns": "int", "agent": "@filler"},
                ],
            }]
        }
        results = check_plan_quality(plan)
        blocking = [r for r in results if r.blocking and r.heuristic == "unassigned-agents"]
        assert len(blocking) == 0

    def test_low_parallelism_advisory(self):
        """Plans with 0-1 functions get advisory parallelism warning."""
        plan = {
            "modules": [{
                "name": "tiny",
                "functions": [
                    {"name": "main", "params": [], "returns": "int", "agent": "@filler"},
                ],
            }]
        }
        results = check_plan_quality(plan)
        advisories = [r for r in results if not r.blocking and r.heuristic == "low-parallelism"]
        assert len(advisories) == 1

    def test_missing_contracts_advisory(self):
        """Plans with no contracts get advisory warning."""
        plan = {
            "modules": [{
                "name": "core",
                "functions": [
                    {"name": "a", "params": [{"name": "x", "type": "int"}], "returns": "int", "agent": "@f"},
                    {"name": "b", "params": [{"name": "y", "type": "int"}], "returns": "int", "agent": "@f"},
                ],
            }]
        }
        results = check_plan_quality(plan)
        advisories = [r for r in results if not r.blocking and r.heuristic == "missing-contracts"]
        assert len(advisories) == 1

    def test_with_contracts_no_warning(self):
        """Plans with contracts do not get missing-contracts warning."""
        plan = {
            "modules": [{
                "name": "core",
                "functions": [
                    {"name": "a", "params": [{"name": "x", "type": "int"}], "returns": "int",
                     "agent": "@f", "contracts": {"pre": "(> x 0)", "post": "(> result 0)"}},
                    {"name": "b", "params": [{"name": "y", "type": "int"}], "returns": "int", "agent": "@f"},
                ],
            }]
        }
        results = check_plan_quality(plan)
        advisories = [r for r in results if r.heuristic == "missing-contracts"]
        assert len(advisories) == 0

    def test_empty_modules_advisory(self):
        """Modules with no functions get advisory warning."""
        plan = {
            "modules": [
                {"name": "utils", "functions": []},
                {"name": "core", "functions": [{"name": "a", "params": [], "returns": "int", "agent": "@f"}]},
            ]
        }
        results = check_plan_quality(plan)
        advisories = [r for r in results if r.heuristic == "empty-modules"]
        assert len(advisories) == 1


# ─────────────────────────────────────────────────────────────────────
# Plan -> LLMLL source
#
# The skeleton used to be a hand-built JSON-AST dict, and these tests pinned
# its shape: `{"kind": "int"}`, `def-logic`, a `type` key on params. None of
# that was the shape the reader takes, and the document did not parse. The
# skeleton is now S-expression source that the compiler emits; the tests below
# pin the source, and TestSkeletonAgainstCompiler runs the compiler on it.
# ─────────────────────────────────────────────────────────────────────

_MATH_PLAN = {
    "modules": [{
        "name": "math",
        "functions": [
            {
                "name": "add",
                "params": [{"name": "a", "type": "int"}, {"name": "b", "type": "int"}],
                "returns": "int",
                "agent": "@filler",
                "description": "Add two numbers",
            }
        ],
        "imports": [],
        "exports": ["add"],
    }]
}


class TestPlanToSource:

    def test_simple_plan(self):
        src = _plan_to_source(_MATH_PLAN)
        assert "(export add)" in src
        assert "(def-shell add [a: int b: int] -> int" in src
        assert '(?delegate @filler "Add two numbers" -> int))' in src
        assert "def-logic" not in src

    def test_types_pass_through_verbatim(self):
        plan = {"modules": [{"name": "m", "functions": [{
            "name": "f", "params": [{"name": "xs", "type": "list[int]"}],
            "returns": "Result[(int, bool), string]", "agent": "@a"}]}]}
        src = _plan_to_source(plan)
        assert "[xs: list[int]] -> Result[(int, bool), string]" in src
        assert "-> Result[(int, bool), string]))" in src

    def test_plan_with_wasi_import(self):
        plan = {"modules": [{"name": "io", "functions": [], "imports": ["wasi.io"]}]}
        assert "(import wasi.io (capability stdout :deterministic false))" in _plan_to_source(plan)

    def test_description_is_one_quoted_line(self):
        assert _sexpr_string('say "hi"\nthen \\ stop') == '"say \\"hi\\" then \\\\ stop"'


# ─────────────────────────────────────────────────────────────────────
# JSON response parsing
# ─────────────────────────────────────────────────────────────────────

class TestJsonParsing:

    def test_plain_json(self):
        raw = '{"modules": []}'
        result = _parse_json_response(raw)
        assert result == {"modules": []}

    def test_fenced_json(self):
        raw = '```json\n{"modules": []}\n```'
        result = _parse_json_response(raw)
        assert result == {"modules": []}

    def test_invalid_json(self):
        assert _parse_json_response("not json") is None

    def test_array_returns_none(self):
        assert _parse_json_response("[1, 2, 3]") is None


# ─────────────────────────────────────────────────────────────────────
# Lead Agent with DryRunAgent
# ─────────────────────────────────────────────────────────────────────

class TestLeadAgentDryRun:

    def test_dry_run_call_llm_fill_mode(self):
        """DryRunAgent.call_llm returns stub patch array for hole-filling prompts."""
        agent = DryRunAgent()
        raw = agent.call_llm("You are a code filler.", "Fill this hole")
        result = json.loads(raw)
        assert isinstance(result, list)

    def test_dry_run_call_llm_plan_mode(self):
        """DryRunAgent.call_llm returns stub plan dict for plan generation prompts.
        Fixes Issue #1 from Language Team review."""
        agent = DryRunAgent()
        raw = agent.call_llm("You are the LLMLL Lead Agent. Your job is to decompose a software intent into a structured architecture plan.", "Build an auth module")
        result = json.loads(raw)
        assert isinstance(result, dict)
        assert "modules" in result
        assert len(result["modules"]) > 0
        # Verify the stub plan passes quality checks
        from llmll_orchestra.quality import check_plan_quality
        blocking = [q for q in check_plan_quality(result) if q.blocking]
        assert len(blocking) == 0, f"Stub plan has blocking issues: {blocking}"

    def test_plan_to_source_with_contracts(self):
        """Plan contracts become pre/post clauses, verbatim."""
        plan = {
            "modules": [{
                "name": "validated",
                "functions": [{
                    "name": "positive-add",
                    "params": [{"name": "x", "type": "int"}, {"name": "y", "type": "int"}],
                    "returns": "int",
                    "agent": "@filler",
                    "contracts": {"pre": "(> x 0)", "post": "(> result 0)"},
                    "description": "Add positive numbers",
                }],
                "imports": [],
                "exports": [],
            }],
        }
        src = _plan_to_source(plan)
        assert "  (pre (> x 0))" in src
        assert "  (post (> result 0))" in src

    def test_wasi_io_capability_is_stdout(self):
        """wasi.io import gets 'stdout' capability, not a generic name."""
        plan = {"modules": [{"name": "io", "functions": [], "imports": ["wasi.io"]}]}
        assert "(capability stdout " in _plan_to_source(plan)

    def test_wasi_fs_capability_is_filesystem(self):
        """wasi.fs import gets 'filesystem' capability, not 'stdout'.
        Fixes Issue #3 from Language Team review."""
        plan = {"modules": [{"name": "fs", "functions": [], "imports": ["wasi.fs"]}]}
        assert "(capability filesystem " in _plan_to_source(plan)

    def test_generate_plan_dry_run(self):
        """DryRunAgent + LeadAgent.generate_plan succeeds (E2E dry-run)."""
        from unittest.mock import MagicMock
        agent = DryRunAgent()
        compiler = MagicMock()
        compiler.spec.return_value = None
        lead = LeadAgent(agent=agent, compiler=compiler)
        plan = lead.generate_plan("Build a calculator")
        assert isinstance(plan, dict)
        assert "modules" in plan


# ─────────────────────────────────────────────────────────────────────
# The skeleton against the real compiler
#
# Skips without LLMLL_BIN; the spec-roundtrip CI job sets it. These are the
# cells that would have caught the old builder: its output failed to parse
# ("key \"schemaVersion\" not found") and generate_skeleton logged that as
# "expected type warnings" and returned the path anyway.
# ─────────────────────────────────────────────────────────────────────

import os
from pathlib import Path

_needs_llmll = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll")

_SCHEMA = Path(__file__).resolve().parents[3] / "docs" / "llmll-ast.schema.json"

_AUTH_PLAN = {
    "modules": [{
        "name": "auth",
        "imports": ["wasi.io"],
        "exports": ["clamp", "login", "pairup"],
        "functions": [
            {"name": "clamp", "params": [{"name": "x", "type": "int"}, {"name": "hi", "type": "int"}],
             "returns": "int", "agent": "@math",
             "contracts": {"pre": "(>= hi 0)", "post": "(<= result hi)"},
             "description": 'Clamp x to at most "hi"'},
            {"name": "login", "params": [{"name": "u", "type": "string"}, {"name": "p", "type": "string"}],
             "returns": "Result[string, string]", "agent": "@verifier",
             "contracts": {"pre": None, "post": None}, "description": "Log in"},
            {"name": "pairup", "params": [{"name": "xs", "type": "list[int]"}],
             "returns": "(int, bool)", "agent": "@math", "description": "Pair"},
        ],
    }],
}


def _lead():
    from unittest.mock import MagicMock
    return LeadAgent(agent=MagicMock(), compiler=Compiler(binary=os.environ["LLMLL_BIN"]))


@_needs_llmll
class TestSkeletonAgainstCompiler:

    def test_skeleton_emits_checks_and_has_one_hole_per_function(self):
        lead = _lead()
        path = lead.generate_skeleton(_AUTH_PLAN)
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
        assert "schemaVersion" in doc
        holes = lead.compiler.holes(path)
        assert sorted(h.agent for h in holes) == ["@math", "@math", "@verifier"]

    def test_skeleton_validates_against_the_published_schema(self):
        jsonschema = pytest.importorskip("jsonschema")
        path = _lead().generate_skeleton(_AUTH_PLAN)
        v = jsonschema.Draft202012Validator(json.loads(_SCHEMA.read_text(encoding="utf-8")))
        errors = [e.message for e in v.iter_errors(json.loads(Path(path).read_text(encoding="utf-8")))]
        assert errors == []

    def test_params_are_typed_in_the_emitted_document(self):
        path = _lead().generate_skeleton(_AUTH_PLAN)
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
        params = [p for st in doc["statements"] for p in st.get("params", [])]
        assert params and all("param_type" in p for p in params)

    def test_a_plan_the_compiler_rejects_raises_instead_of_returning(self):
        # An unbalanced contract, the likeliest malformed LLM plan. (An unbound
        # name in a post is only a warning at check, so it cannot serve here.)
        bad = {"modules": [{"name": "m", "functions": [{
            "name": "f", "params": [{"name": "x", "type": "int"}],
            "returns": "int", "agent": "@a",
            "contracts": {"post": "(> result x"}}]}]}
        with pytest.raises(ValueError):
            _lead().generate_skeleton(bad)

    def test_checkout_brief_for_a_delegate_hole_names_params_and_return_type(self):
        """DELEGATE-BRIEF: the fill agent learns the parameter names and the type
        it must produce. Before the compiler fix a ?delegate hole's brief had no
        in_scope and no expected_return_type, and a live fill wrote `password`
        for a parameter named `raw-pw`."""
        lead = _lead()
        path = lead.generate_skeleton(_AUTH_PLAN)
        # clamp is the first function; import and export precede it.
        clamp = next(h for h in lead.compiler.holes(path) if h.pointer == "/statements/2/body")
        token = lead.compiler.checkout(path, clamp.pointer)
        try:
            names = {e["name"] for e in token.context.get("scope", [])}
            assert {"x", "hi"} <= names
            assert token.context.get("expected_return_type") == "int"
        finally:
            lead.compiler.release(path, token.token)

    def test_release_frees_the_lock_so_the_hole_can_be_checked_out_again(self):
        """Compiler.release passed the pointer where the CLI takes the token;
        the lock stayed held and a second checkout reported it taken."""
        lead = _lead()
        path = lead.generate_skeleton(_AUTH_PLAN)
        ptr = "/statements/2/body"
        first = lead.compiler.checkout(path, ptr)
        lead.compiler.release(path, first.token)
        second = lead.compiler.checkout(path, ptr)
        lead.compiler.release(path, second.token)
        assert second.token

    def test_require_proof_refuses_an_assumed_fill_through_the_real_compiler(self):
        """PATCH-PROOF-1 end to end: `(unwrap-or (ok <clamp>) 0)` is correct but
        outside the fragment, so `patch --require-proof` refuses it and names the
        construct. (`min` was the example until MINMAX-FRAG-1 moved it inside.)"""
        import tempfile, shutil
        fixture = Path(__file__).resolve().parents[1] / "fixtures" / "ledger" / "ledger.ast.json"
        work = Path(tempfile.mkdtemp()) / "ledger.ast.json"
        shutil.copy(fixture, work)
        compiler = Compiler(binary=os.environ["LLMLL_BIN"])
        token = compiler.checkout(work, "/statements/0/body")
        req = work.with_name("req.json")
        req.write_text(json.dumps({"token": token.token, "patch": [{
            "op": "replace", "path": "/statements/0/body",
            "value": {"kind": "app", "fn": "unwrap-or", "args": [
                {"kind": "app", "fn": "ok", "args": [{
                    "kind": "if",
                    "cond": {"kind": "op", "op": "<=", "args": [
                        {"kind": "var", "name": "amount"}, {"kind": "var", "name": "balance"}]},
                    "then_branch": {"kind": "var", "name": "amount"},
                    "else_branch": {"kind": "var", "name": "balance"}}]},
                {"kind": "lit-int", "value": 0}]}}]}))
        refused = compiler.patch(work, req, require_proof=True)
        assert refused["success"] is False
        assert "app:unwrap-or" in refused["diagnostics"][0]["message"]
        accepted = compiler.patch(work, req)
        assert accepted["success"] is True
        assert accepted["verification"][0]["body_faithful"] is False
