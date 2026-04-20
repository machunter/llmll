"""
test_lead_agent.py — Tests for Lead Agent and quality heuristics.

v0.4: Sprint 2 Tasks 4-6.
"""

from __future__ import annotations

import json
import pytest

from llmll_orchestra.quality import check_plan_quality, QualityResult
from llmll_orchestra.lead_agent import (
    LeadAgent, _plan_to_ast, _type_to_ast, _parse_json_response,
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
# Type conversion
# ─────────────────────────────────────────────────────────────────────

class TestTypeConversion:

    def test_basic_types(self):
        assert _type_to_ast("int") == {"kind": "int"}
        assert _type_to_ast("string") == {"kind": "string"}
        assert _type_to_ast("bool") == {"kind": "bool"}

    def test_list_type(self):
        result = _type_to_ast("list[int]")
        assert result == {"kind": "list", "element_type": {"kind": "int"}}

    def test_result_type(self):
        result = _type_to_ast("Result[string, string]")
        assert result["kind"] == "result"
        assert result["ok_type"] == {"kind": "string"}
        assert result["err_type"] == {"kind": "string"}

    def test_pair_type(self):
        result = _type_to_ast("(int, string)")
        assert result["kind"] == "pair-type"
        assert result["first_type"] == {"kind": "int"}
        assert result["second_type"] == {"kind": "string"}

    def test_custom_type(self):
        result = _type_to_ast("UserInfo")
        assert result == {"kind": "custom", "name": "UserInfo"}


# ─────────────────────────────────────────────────────────────────────
# Plan -> AST conversion
# ─────────────────────────────────────────────────────────────────────

class TestPlanToAst:

    def test_simple_plan(self):
        plan = {
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
        ast = _plan_to_ast(plan)
        stmts = ast["statements"]
        # Should have: export, def-logic
        assert any(s["kind"] == "export" for s in stmts)
        assert any(s["kind"] == "def-logic" for s in stmts)

        defn = [s for s in stmts if s["kind"] == "def-logic"][0]
        assert defn["name"] == "add"
        assert defn["body"]["kind"] == "hole"
        assert defn["body"]["agent"] == "@filler"

    def test_plan_with_wasi_import(self):
        plan = {
            "modules": [{
                "name": "io",
                "functions": [],
                "imports": ["wasi.io"],
            }]
        }
        ast = _plan_to_ast(plan)
        imports = [s for s in ast["statements"] if s["kind"] == "import"]
        assert len(imports) == 1
        assert imports[0]["path"] == "wasi.io"
        assert "capability" in imports[0]


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

    def test_dry_run_call_llm(self):
        """DryRunAgent._call_llm returns stub JSON."""
        agent = DryRunAgent()
        raw = agent._call_llm("system", "user prompt")
        result = json.loads(raw)
        assert isinstance(result, list)
