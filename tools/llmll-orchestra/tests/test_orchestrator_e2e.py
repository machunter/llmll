"""
test_orchestrator_e2e.py — v0.3.5 Track A integration tests (O4).

Tests the orchestrator end-to-end loop with mocked compiler and agent:
  1. Happy path: single hole, first attempt succeeds
  2. Retry with diagnostics: first attempt rejected, second succeeds
  3. Lock expiry handling: TTL expires mid-fill, re-checkout works
  4. EC-6: Token update after re-checkout
  5. All retries fail: graceful failure report
"""

from __future__ import annotations

import json
import pytest
from dataclasses import dataclass, field
from typing import Any
from unittest.mock import MagicMock, patch

from llmll_orchestra.compiler import (
    Compiler, CompilerError, HoleEntry, HoleDep, CheckoutToken,
)
from llmll_orchestra.agent import AgentResponse, DryRunAgent
from llmll_orchestra.orchestrator import (
    Orchestrator, OrchestratorReport, HoleResult, _format_diagnostics,
)


# ─────────────────────────────────────────────────────────────────────
# Fixtures: mock compiler + mock agent
# ─────────────────────────────────────────────────────────────────────

HOLE_VALIDATE = HoleEntry(
    pointer="/statements/0/body",
    kind="named",
    status="agent-task",
    agent="@impl-agent",
    message="Implement validate_token",
    module_path="auth_module",
    inferred_type="string -> bool",
)

HOLE_HASH = HoleEntry(
    pointer="/statements/1/body",
    kind="named",
    status="agent-task",
    agent="@impl-agent",
    message="Implement hash_password",
    module_path="auth_module",
    inferred_type="string -> string",
)

VALID_PATCH_OPS = [
    {"op": "replace", "path": "/statements/0/body", "value": {"kind": "lit-bool", "value": True}}
]


class MockCompiler:
    """Mock compiler that records calls and returns configurable results."""

    def __init__(self):
        self.holes_result: list[HoleEntry] = [HOLE_VALIDATE]
        self.checkout_result = CheckoutToken(
            token="test-token-abc123",
            pointer="/statements/0/body",
            context={"scope": [{"name": "input", "type": "string", "source": "param"}]},
        )
        self.patch_results: list[dict] = [{"success": True, "diagnostics": []}]
        self._patch_call_idx = 0
        self.status_result: dict = {"remaining_seconds": 300}
        self.spec_result: str | None = "## Builtins\n- abs\n- list-head"

        # Call tracking
        self.checkout_calls: list[tuple] = []
        self.patch_calls: list[tuple] = []
        self.release_calls: list[tuple] = []
        self.status_calls: list[tuple] = []

    def holes(self, source):
        return self.holes_result

    def checkout(self, source, pointer):
        self.checkout_calls.append((source, pointer))
        return self.checkout_result

    def patch(self, source, patch_file):
        self.patch_calls.append((source, patch_file))
        idx = min(self._patch_call_idx, len(self.patch_results) - 1)
        self._patch_call_idx += 1
        return self.patch_results[idx]

    def release(self, source, pointer):
        self.release_calls.append((source, pointer))

    def checkout_status(self, source, token):
        self.status_calls.append((source, token))
        return self.status_result

    def spec(self, *, json_output=False):
        return self.spec_result


class MockAgent:
    """Mock agent that returns configurable responses."""

    def __init__(self):
        self.system_prompt = "test prompt"
        self.responses: list[AgentResponse] = [
            AgentResponse(success=True, patch_ops=VALID_PATCH_OPS)
        ]
        self._call_idx = 0
        self.fill_calls: list[tuple] = []

    def fill_hole(self, hole, context=None):
        self.fill_calls.append((hole, context))
        idx = min(self._call_idx, len(self.responses) - 1)
        self._call_idx += 1
        return self.responses[idx]


# ─────────────────────────────────────────────────────────────────────
# Test 1: Happy path — single hole, first attempt succeeds
# ─────────────────────────────────────────────────────────────────────

def test_happy_path_single_hole():
    compiler = MockCompiler()
    agent = MockAgent()

    orch = Orchestrator(compiler=compiler, agent=agent, max_retries=3)
    report = orch.run("auth_module.ast.json")

    assert report.filled == 1
    assert report.failed == 0
    assert len(report.results) == 1
    assert report.results[0].success is True
    assert report.results[0].attempts == 1


# ─────────────────────────────────────────────────────────────────────
# Test 2: Retry with diagnostics — first attempt rejected, second OK
# ─────────────────────────────────────────────────────────────────────

def test_retry_with_diagnostics():
    """O2: After a failed patch, diagnostics are formatted and fed back."""
    compiler = MockCompiler()
    # First patch fails with diagnostics, second succeeds
    compiler.patch_results = [
        {
            "success": False,
            "diagnostics": [
                {
                    "kind": "type-mismatch",
                    "message": "expected string, got int",
                    "pointer": "/statements/0/body",
                    "expected": "string",
                    "got": "int",
                }
            ],
        },
        {"success": True, "diagnostics": []},
    ]

    agent = MockAgent()
    # Both attempts return valid patch ops
    agent.responses = [
        AgentResponse(success=True, patch_ops=[{"op": "replace", "path": "/statements/0/body", "value": {"kind": "lit-int", "value": 42}}]),
        AgentResponse(success=True, patch_ops=VALID_PATCH_OPS),
    ]

    orch = Orchestrator(compiler=compiler, agent=agent, max_retries=3)
    report = orch.run("auth_module.ast.json")

    assert report.filled == 1
    assert report.results[0].attempts == 2

    # Verify the second agent call received formatted diagnostics
    assert len(agent.fill_calls) == 2
    second_ctx = agent.fill_calls[1][1]
    assert "prior_diagnostics" in second_ctx

    # O2: diagnostics should be formatted as human-readable text, not raw JSON
    diag_text = second_ctx["prior_diagnostics"]
    assert isinstance(diag_text, str)
    assert "type-mismatch" in diag_text
    assert "expected string, got int" in diag_text
    assert "Expected: string, Got: int" in diag_text


# ─────────────────────────────────────────────────────────────────────
# Test 3: Lock expiry handling — TTL expires, re-checkout works
# ─────────────────────────────────────────────────────────────────────

def test_lock_expiry_recheckout():
    """O3: When TTL is low, orchestrator re-checkouts and continues."""
    compiler = MockCompiler()
    # TTL is expired
    compiler.status_result = {"remaining_seconds": 2}
    # Re-checkout returns a new token
    new_token = CheckoutToken(
        token="new-token-xyz789",
        pointer="/statements/0/body",
        context={"scope": []},
    )
    original_checkout = compiler.checkout_result
    call_count = [0]
    original_checkout_fn = compiler.checkout

    def mock_checkout(source, pointer):
        call_count[0] += 1
        if call_count[0] == 1:
            return original_checkout
        return new_token

    compiler.checkout = mock_checkout

    agent = MockAgent()
    orch = Orchestrator(compiler=compiler, agent=agent, max_retries=3)
    report = orch.run("auth_module.ast.json")

    assert report.filled == 1
    # Re-checkout should have been called
    assert call_count[0] == 2  # initial + re-checkout


# ─────────────────────────────────────────────────────────────────────
# Test 4: EC-6 — Token update after re-checkout
# ─────────────────────────────────────────────────────────────────────

def test_ec6_token_update_after_recheckout():
    """EC-6: After re-checkout, the patch request uses the new token."""
    compiler = MockCompiler()
    compiler.status_result = {"remaining_seconds": 1}  # force re-checkout

    new_token = CheckoutToken(
        token="recheckout-token-NEW",
        pointer="/statements/0/body",
        context={"scope": []},
    )
    call_count = [0]

    def mock_checkout(source, pointer):
        call_count[0] += 1
        if call_count[0] == 1:
            return compiler.checkout_result
        return new_token

    compiler.checkout = mock_checkout

    # Capture the patch request to verify token
    written_patches = []
    original_patch = compiler.patch

    def capture_patch(source, patch_file):
        import json as j
        with open(patch_file, 'r') as f:
            written_patches.append(j.load(f))
        return {"success": True, "diagnostics": []}

    compiler.patch = capture_patch

    agent = MockAgent()
    orch = Orchestrator(compiler=compiler, agent=agent, max_retries=3)
    report = orch.run("auth_module.ast.json")

    assert report.filled == 1
    # The patch request should contain the NEW token, not the original
    assert len(written_patches) == 1
    assert written_patches[0]["token"] == "recheckout-token-NEW"


# ─────────────────────────────────────────────────────────────────────
# Test 5: All retries fail — graceful failure
# ─────────────────────────────────────────────────────────────────────

def test_all_retries_fail():
    """All attempts fail — orchestrator releases checkout and reports failure."""
    compiler = MockCompiler()
    compiler.patch_results = [
        {"success": False, "diagnostics": [{"message": "type error attempt 1"}]},
        {"success": False, "diagnostics": [{"message": "type error attempt 2"}]},
        {"success": False, "diagnostics": [{"message": "type error attempt 3"}]},
    ]

    agent = MockAgent()
    agent.responses = [
        AgentResponse(success=True, patch_ops=VALID_PATCH_OPS),
        AgentResponse(success=True, patch_ops=VALID_PATCH_OPS),
        AgentResponse(success=True, patch_ops=VALID_PATCH_OPS),
    ]

    orch = Orchestrator(compiler=compiler, agent=agent, max_retries=3)
    report = orch.run("auth_module.ast.json")

    assert report.filled == 0
    assert report.failed == 1
    assert report.results[0].attempts == 3
    assert report.results[0].success is False
    # Release should have been called
    assert len(compiler.release_calls) == 1


# ─────────────────────────────────────────────────────────────────────
# Test 6: _format_diagnostics produces human-readable text
# ─────────────────────────────────────────────────────────────────────

def test_format_diagnostics():
    """O2: Diagnostic formatting produces structured, human-readable text."""
    diags = [
        {
            "kind": "type-mismatch",
            "message": "expected bool, got string",
            "pointer": "/statements/0/body",
            "expected": "bool",
            "got": "string",
            "suggestion": "Use a comparison operator to return bool",
        },
        {
            "kind": "undefined-name",
            "message": "unknown identifier 'validate'",
        },
    ]

    result = _format_diagnostics(diags)

    assert "rejected by the compiler" in result
    assert "[type-mismatch]" in result
    assert "expected bool, got string" in result
    assert "Expected: bool, Got: string" in result
    assert "Suggestion:" in result
    assert "[undefined-name]" in result
    assert "fix these issues" in result


def test_format_diagnostics_empty():
    assert "No specific" in _format_diagnostics([])


# ─────────────────────────────────────────────────────────────────────
# Test 7: Multiple holes — independent processing
# ─────────────────────────────────────────────────────────────────────

def test_multiple_holes():
    """Multiple fillable holes are processed independently."""
    compiler = MockCompiler()
    compiler.holes_result = [HOLE_VALIDATE, HOLE_HASH]

    agent = MockAgent()
    agent.responses = [
        AgentResponse(success=True, patch_ops=VALID_PATCH_OPS),
        AgentResponse(success=True, patch_ops=VALID_PATCH_OPS),
    ]

    orch = Orchestrator(compiler=compiler, agent=agent, max_retries=3)
    report = orch.run("auth_module.ast.json")

    assert report.total_holes == 2
    assert report.filled == 2
    assert report.failed == 0
    assert len(report.results) == 2


# ─────────────────────────────────────────────────────────────────────
# Test 8: Re-checkout fails (lock taken by another agent)
# ─────────────────────────────────────────────────────────────────────

def test_recheckout_fails_lock_taken():
    """O3: If re-checkout fails, hole is skipped with appropriate error."""
    compiler = MockCompiler()
    compiler.status_result = {"remaining_seconds": 0}  # force re-checkout

    call_count = [0]

    def failing_checkout(source, pointer):
        call_count[0] += 1
        if call_count[0] == 1:
            return compiler.checkout_result
        raise CompilerError("checkout", "lock taken", 1)

    compiler.checkout = failing_checkout

    agent = MockAgent()
    orch = Orchestrator(compiler=compiler, agent=agent, max_retries=3)
    report = orch.run("auth_module.ast.json")

    assert report.failed == 1
    assert "re-checkout failed" in report.results[0].error


# ─────────────────────────────────────────────────────────────────────
# Test 9: Report JSON serialization
# ─────────────────────────────────────────────────────────────────────

def test_report_json_serialization():
    """OrchestratorReport.to_dict() produces valid JSON-serializable dict."""
    report = OrchestratorReport(
        source_file="test.ast.json",
        total_holes=2,
        filled=1,
        failed=1,
        skipped=0,
        results=[
            HoleResult(pointer="/s/0/body", agent="@a", attempts=1, success=True),
            HoleResult(pointer="/s/1/body", agent=None, attempts=3, success=False, error="type error"),
        ],
    )
    d = report.to_dict()
    # Should be JSON-serializable without errors
    text = json.dumps(d)
    parsed = json.loads(text)
    assert parsed["filled"] == 1
    assert parsed["failed"] == 1
    assert len(parsed["results"]) == 2
"""Tests for the LLMLL orchestrator v0.3.5 (Track A: O1-O4)."""
