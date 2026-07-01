"""
test_compiler.py — Regression tests for Compiler.checkout()'s context
mapping (doc-audit Bug 3: "Checkout context key mismatch").

`Checkout.hs`'s `ToJSON CheckoutToken` instance emits FLAT top-level JSON
keys (`in_scope`, `expected_return_type`, `available_functions`,
`type_definitions`, `scope_truncated`, ...) -- there is no `"context"`
wrapper object in the real `llmll checkout --json` response. The old
`Compiler.checkout()` read `data.get("context", {})`, which is always `{}`
against the real CLI, so `agent.py`'s scope-aware prompt enrichment
(`_format_context`) never fired.

These tests use a fixture shaped exactly like `Checkout.hs`'s `ToJSON
CheckoutToken` instance (compiler/src/LLMLL/Checkout.hs:219-245) -- flat
top-level keys, no "context" sub-object -- to catch any regression back to
reading a nonexistent wrapper key.
"""

from __future__ import annotations

import json
from unittest.mock import patch, MagicMock

from llmll_orchestra.compiler import Compiler, CheckoutToken, HoleEntry, _build_context
from llmll_orchestra.agent import build_prompt, _format_context


# A realistic `llmll checkout --json` response: flat top-level keys, exactly
# matching Checkout.hs's `ToJSON CheckoutToken` instance. No "context" key.
REALISTIC_CHECKOUT_RESPONSE = {
    "pointer": "/statements/0/body",
    "hole_kind": "hole-named",
    "token": "abc123token",
    "ttl": 3600,
    "timestamp": "2026-07-01T00:00:00Z",
    "in_scope": [
        {"name": "input", "type": "string", "source": "param"},
    ],
    "expected_return_type": "bool",
    "available_functions": [
        {
            "name": "helper",
            "params": [{"name": "x", "type": "int"}],
            "returns": "int",
            "return_type": "int",
            "status": "filled",
            "pre": None,
            "post": None,
            "tier": "verified",
        },
    ],
    "type_definitions": [
        {
            "name": "Status",
            "kind": "sum",
            "constructors": [{"name": "Active"}, {"name": "Inactive"}],
        },
    ],
    "contract_pre": None,
    "postcondition_goal": None,
    "path_condition": None,
    "assumptions": None,
    "obligation_id": None,
    "source_hash": None,
    "verified_hash": None,
    "consumed_guarantees": None,
    "brief_version": "0.12.1",
}


HOLE = HoleEntry(
    pointer="/statements/0/body",
    kind="named",
    status="agent-task",
    agent="@impl-agent",
    message="Implement it",
    module_path="testmod",
)


def _mock_completed_process(stdout: str) -> MagicMock:
    proc = MagicMock()
    proc.stdout = stdout
    proc.stderr = ""
    proc.returncode = 0
    return proc


# ─────────────────────────────────────────────────────────────────────
# _build_context: flat CLI fields -> the shape agent._format_context() reads
# ─────────────────────────────────────────────────────────────────────

def test_build_context_maps_real_cli_flat_fields():
    context = _build_context(REALISTIC_CHECKOUT_RESPONSE)

    assert context["scope"] == REALISTIC_CHECKOUT_RESPONSE["in_scope"]
    assert context["functions"] == REALISTIC_CHECKOUT_RESPONSE["available_functions"]
    assert context["type_definitions"] == REALISTIC_CHECKOUT_RESPONSE["type_definitions"]
    assert context["expected_return_type"] == "bool"
    # scope_truncated is absent from the fixture (default False in Checkout.hs
    # -- it's only emitted at all when True), so it must not appear.
    assert "scope_truncated" not in context


def test_build_context_empty_when_cli_response_has_no_scope_fields():
    """A checkout response with none of the v0.3.5 context-aware fields
    (e.g. a hole with no enclosing scope) must produce an empty dict, not
    KeyError or a stray "context" passthrough."""
    minimal = {"pointer": "/s/0", "hole_kind": "hole-named", "token": "t", "ttl": 3600, "timestamp": "x"}
    assert _build_context(minimal) == {}


# ─────────────────────────────────────────────────────────────────────
# Compiler.checkout(): end-to-end through the subprocess wrapper
# ─────────────────────────────────────────────────────────────────────

def test_checkout_end_to_end_produces_nonempty_context():
    """Regression for Bug 3: against a REAL (flat, no-"context"-wrapper)
    CLI response, Compiler.checkout() must populate CheckoutToken.context
    with the scope/functions/type_definitions data -- not {}.

    Fails under the old `context=data.get("context", {})` code (always {}
    against this fixture, since there is no "context" key) and passes under
    the fix.
    """
    with patch("subprocess.run", return_value=_mock_completed_process(
        json.dumps(REALISTIC_CHECKOUT_RESPONSE)
    )):
        compiler = Compiler(binary="llmll")
        token = compiler.checkout("auth_module.ast.json", "/statements/0/body")

    assert isinstance(token, CheckoutToken)
    assert token.token == "abc123token"
    assert token.context != {}
    assert token.context["scope"] == REALISTIC_CHECKOUT_RESPONSE["in_scope"]
    assert token.context["functions"] == REALISTIC_CHECKOUT_RESPONSE["available_functions"]
    assert token.context["type_definitions"] == REALISTIC_CHECKOUT_RESPONSE["type_definitions"]


# ─────────────────────────────────────────────────────────────────────
# End-to-end: a real checkout response must produce a non-empty rendered
# context section in the agent prompt (the actual user-visible symptom of
# Bug 3 -- "scope-awareness prompt enrichment is dead code").
# ─────────────────────────────────────────────────────────────────────

def test_checkout_context_renders_nonempty_prompt_section():
    with patch("subprocess.run", return_value=_mock_completed_process(
        json.dumps(REALISTIC_CHECKOUT_RESPONSE)
    )):
        compiler = Compiler(binary="llmll")
        token = compiler.checkout("auth_module.ast.json", "/statements/0/body")

    prompt = build_prompt(HOLE, token.context)

    # build_prompt's `if context:` guard must actually fire, and
    # _format_context must render the structured sections -- not silently
    # produce an empty context block.
    assert "### In-scope variables" in prompt
    assert "`input`" in prompt and "`string`" in prompt
    assert "### Available functions" in prompt
    assert "`helper`" in prompt
    assert "### Type definitions" in prompt
    assert "`Status`" in prompt
    assert "### Expected return type" in prompt
    assert "`bool`" in prompt
    # _format_context() field-shape regression (resumed task, 2026-07-01,
    # distinct from the checkout-context-key-mismatch bug above): the
    # function signature and type-definition shape must be built from the
    # REAL FuncEntry/TypeDefEntry fields (params + returns; kind +
    # constructors/base_type) -- not read off nonexistent
    # "signature"/"definition" keys, which used to render as a bare "?".
    assert "`(x: int) -> int`" in prompt
    assert "tier: verified" in prompt
    assert "`Active | Inactive`" in prompt


# ─────────────────────────────────────────────────────────────────────
# _format_context() field-shape regression (resumed task, 2026-07-01):
# real FuncEntry/TypeDefEntry field shapes must render actual content,
# not "?" placeholders from nonexistent "signature"/"definition" keys.
# ─────────────────────────────────────────────────────────────────────

def test_format_context_function_signature_from_params_and_returns():
    """FuncEntry (Checkout.hs) has no "signature" key -- it has "params"
    ([{name, type}, ...]) and "returns"/"return_type". A function with a
    pre-condition must render both the built signature and the pre clause,
    not a "?" placeholder."""
    context = {
        "functions": [
            {
                "name": "withdraw",
                "params": [{"name": "balance", "type": "int"}, {"name": "amount", "type": "int"}],
                "returns": "int",
                "return_type": "int",
                "status": "filled",
                "pre": "(>= balance amount)",
                "post": None,
                "tier": "asserted",
            },
        ],
    }
    rendered = _format_context(context)
    assert "### Available functions" in rendered
    assert "`(balance: int, amount: int) -> int`" in rendered
    assert "pre: `(>= balance amount)`" in rendered
    assert "tier: asserted" in rendered
    # regression: must not fall back to the old nonexistent-key placeholder
    assert "`?`" not in rendered


def test_format_context_type_definition_sum_type_from_constructors():
    """TypeDefEntry (Checkout.hs) has no "definition" key for a sum type --
    it has "kind": "sum" and "constructors": [{name, payload?}, ...]."""
    context = {
        "type_definitions": [
            {
                "name": "Shape",
                "kind": "sum",
                "constructors": [{"name": "Circle", "payload": "int"}, {"name": "Rect"}],
            },
        ],
    }
    rendered = _format_context(context)
    assert "### Type definitions" in rendered
    assert "`Shape` (sum) = `Circle(int) | Rect`" in rendered
    assert "`?`" not in rendered


def test_format_context_type_definition_dependent_type_from_base_type():
    """TypeDefEntry (Checkout.hs) for an alias/dependent type has no
    "definition" key either -- it has "kind": "dependent" (or "alias") and
    "base_type", plus an optional "recursive": true."""
    context = {
        "type_definitions": [
            {
                "name": "PositiveInt",
                "kind": "dependent",
                "base_type": "int",
                "recursive": True,
            },
        ],
    }
    rendered = _format_context(context)
    assert "### Type definitions" in rendered
    assert "`PositiveInt` (dependent) = `int`" in rendered
    assert "[recursive]" in rendered
    assert "`?`" not in rendered
