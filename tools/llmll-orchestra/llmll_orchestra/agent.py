"""
agent.py — LLM agent interaction via Anthropic or OpenAI SDKs.

Each hole is filled by sending its context to an LLM and parsing the
response as a JSON-Patch operation.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any

from .compiler import HoleEntry


@dataclass
class AgentResponse:
    """Result of asking an agent to fill a hole."""
    success: bool
    patch_ops: list[dict[str, Any]] = field(default_factory=list)
    raw_response: str = ""
    error: str | None = None


class AgentError(Exception):
    """Raised when the agent fails to produce a valid patch."""
    pass


# ─────────────────────────────────────────────────────────────────────
# System prompt — composable from compiler-emitted spec
# ─────────────────────────────────────────────────────────────────────

_SYSTEM_PROMPT_HEADER = """\
You are an LLMLL implementation agent. You receive a hole specification
from the LLMLL compiler and must produce a JSON-Patch (RFC 6902) that
fills the hole with a correct implementation.

## Valid LLMLL Expression Node Kinds

Every expression node is a JSON object with a "kind" field. Valid kinds:

- `lit-int`:    {"kind": "lit-int", "value": 42}
- `lit-float`:  {"kind": "lit-float", "value": 3.14}
- `lit-string`: {"kind": "lit-string", "value": "hello"}
- `lit-bool`:   {"kind": "lit-bool", "value": true}
- `lit-unit`:   {"kind": "lit-unit"}
- `var`:        {"kind": "var", "name": "x"}
- `app`:        {"kind": "app", "fn": "function-name", "args": [<expr>, ...]}
- `op`:         {"kind": "op", "op": "+", "args": [<expr>, <expr>]}
- `if`:         {"kind": "if", "cond": <expr>, "then_branch": <expr>, "else_branch": <expr>}
- `let`:        {"kind": "let", "bindings": [{"name": "x", "expr": <expr>}], "body": <expr>}
- `match`:      {"kind": "match", "scrutinee": <expr>, "arms": [{"pattern": <pat>, "body": <expr>}]}
- `pair`:       {"kind": "pair", "fst": <expr>, "snd": <expr>}
- `lambda`:     {"kind": "lambda", "params": [{"name": "x", "type": <type>}], "body": <expr>}
"""

_SYSTEM_PROMPT_FOOTER = """\

## Patch Format

Return a JSON array with exactly one RFC 6902 "replace" operation:
```json
[{"op": "replace", "path": "<pointer>", "value": <expression-node>}]
```

## Rules

1. Return ONLY the JSON array. No commentary, no markdown fences.
2. The "path" MUST exactly match the hole's pointer.
3. The "value" MUST be a valid expression node using ONLY the kinds listed above.
4. Do NOT invent new kinds. Use "app" to call functions, "op" for operators.
5. To return an Ok result: {"kind": "app", "fn": "ok", "args": [<value>]}
6. To return an Err result: {"kind": "app", "fn": "err", "args": [<value>]}
7. Operators are FIXED-ARITY: `+`, `-`, `*`, `/` take exactly 2 args; `not` takes 1. Parametricity rule: polymorphic builtins (= != etc.) accept any type — do not cast.

## pair / first / second Usage

- Construct: {"kind": "pair", "fst": <expr>, "snd": <expr>}
- Project first:  {"kind": "app", "fn": "first", "args": [<pair-expr>]}
- Project second: {"kind": "app", "fn": "second", "args": [<pair-expr>]}
- Type node: {"kind": "pair-type", "first_type": <type>, "second_type": <type>}
- Function type node: {"kind": "fn-type", "param_types": [<type>, ...], "return_type": <type>}

## Result Construction vs Pattern Matching

- To CONSTRUCT a Result: use `ok(v)` → `{"kind": "app", "fn": "ok", "args": [v]}`
                          use `err(e)` → `{"kind": "app", "fn": "err", "args": [e]}`
- To MATCH on a Result: use constructors `Success` and `Error` in patterns:
  `{"pattern": {"kind": "constructor", "constructor": "Success", "sub_patterns": [{"kind": "bind", "name": "v"}]}}`

## letrec (recursive functions)

Recursive functions use `letrec` with a `:decreases` annotation. The agent should not emit letrec nodes — use `def-logic` with standard recursion instead.
"""

# Legacy prompt: used when the compiler doesn't support `llmll spec` (pre-v0.3.4)
_LEGACY_BUILTINS_REF = """\

## Built-in Functions (pre-v0.3.4 static reference)

abs, err, first, int-to-string, is-ok, list-append, list-contains,
list-empty, list-filter, list-fold, list-head, list-length, list-map,
list-nth, list-prepend, list-tail, max, min, ok, pair, range,
regex-match, second, seq-commands, string-char-at, string-concat,
string-concat-many, string-contains, string-empty?, string-length,
string-slice, string-split, string-to-int, string-trim, unwrap, unwrap-or

## Operators

+, -, *, /, mod, =, !=, <, >, <=, >=, and, or, not
"""


def build_system_prompt(compiler_spec: str | None = None) -> str:
    """Build the system prompt, injecting the compiler-emitted spec if available.

    If compiler_spec is None (pre-v0.3.4 compiler), falls back to the
    static legacy reference.
    """
    builtins_section = compiler_spec if compiler_spec else _LEGACY_BUILTINS_REF
    return _SYSTEM_PROMPT_HEADER + builtins_section + _SYSTEM_PROMPT_FOOTER


# Default for backward compatibility — used when no spec is injected
SYSTEM_PROMPT = build_system_prompt(None)



def build_prompt(hole: HoleEntry, context: dict[str, Any] | None = None) -> str:
    """Build the user prompt for a hole-filling request.

    v0.3.5 (O5): When context includes scope/functions/type_definitions
    from the context-aware checkout, formats them as structured sections
    instead of raw JSON blobs.
    """
    parts = [
        f"## Hole to fill\n",
        f"- **Pointer:** `{hole.pointer}`",
        f"- **Kind:** `{hole.kind}`",
        f"- **Status:** `{hole.status}`",
        f"- **Context:** `{hole.module_path}`",
        f"- **Description:** {hole.message}",
    ]

    if hole.agent:
        parts.append(f"- **Target agent:** `{hole.agent}`")

    if hole.inferred_type:
        parts.append(f"- **Expected type:** `{hole.inferred_type}`")

    if hole.depends_on:
        parts.append("\n### Dependencies (already filled)")
        for dep in hole.depends_on:
            parts.append(f"- `{dep.pointer}` via `{dep.via}` ({dep.reason})")

    if context:
        parts.append(_format_context(context))

    # Prior diagnostics from retry (O2 — already formatted as text)
    if context and "prior_diagnostics" in context:
        parts.append(f"\n### Previous attempt feedback\n{context['prior_diagnostics']}")

    parts.append(
        "\n\nReturn a JSON array of RFC 6902 patch operations to fill this hole."
    )

    return "\n".join(parts)


def _format_context(context: dict[str, Any]) -> str:
    """O5: Format checkout context as structured prompt sections.

    Handles v0.3.5 context-aware fields (scope, functions, type_definitions,
    expected_return_type) and falls back to raw JSON for unknown fields.
    """
    sections: list[str] = []

    # Expected return type
    ret_type = context.get("expected_return_type")
    if ret_type:
        sections.append(f"\n### Expected return type\n`{ret_type}`")

    # In-scope variables (Γ)
    scope = context.get("scope", [])
    if scope:
        lines = ["\n### In-scope variables"]
        lines.append("| Name | Type | Source |")
        lines.append("|------|------|--------|")
        for entry in scope:
            name = entry.get("name", "?")
            ty = entry.get("type", "?")
            src = entry.get("source", "?")
            lines.append(f"| `{name}` | `{ty}` | {src} |")
        if context.get("scope_truncated"):
            lines.append("\n> Note: scope was truncated. Additional bindings exist but are omitted.")
        sections.append("\n".join(lines))

    # Available functions (Σ)
    functions = context.get("functions", [])
    if functions:
        lines = ["\n### Available functions"]
        for fn in functions:
            name = fn.get("name", "?")
            sig = fn.get("signature", "?")
            lines.append(f"- `{name}` : `{sig}`")
        sections.append("\n".join(lines))

    # Type definitions
    type_defs = context.get("type_definitions", [])
    if type_defs:
        lines = ["\n### Type definitions"]
        for td in type_defs:
            name = td.get("name", "?")
            defn = td.get("definition", "?")
            lines.append(f"- `{name}` = `{defn}`")
        sections.append("\n".join(lines))

    # Fallback: any context keys not handled above
    known_keys = {
        "scope", "functions", "type_definitions", "expected_return_type",
        "scope_truncated", "prior_diagnostics",
    }
    extra = {k: v for k, v in context.items() if k not in known_keys}
    if extra:
        sections.append(f"\n### Additional context\n```json\n{json.dumps(extra, indent=2)}\n```")

    return "\n".join(sections) if sections else ""


def _parse_patch_response(raw: str) -> AgentResponse:
    """Parse an LLM response into a list of JSON-Patch ops."""
    try:
        text = raw.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            text = "\n".join(lines[1:])
            if text.endswith("```"):
                text = text[:-3].strip()

        patch_ops = json.loads(text)
        if not isinstance(patch_ops, list):
            raise ValueError("Expected a JSON array")
        return AgentResponse(success=True, patch_ops=patch_ops, raw_response=raw)
    except (json.JSONDecodeError, ValueError) as e:
        return AgentResponse(
            success=False,
            raw_response=raw,
            error=f"Failed to parse patch: {e}",
        )


# ─────────────────────────────────────────────────────────────────────
# Anthropic agent
# ─────────────────────────────────────────────────────────────────────

class Agent:
    """Claude-based agent for hole filling (Anthropic SDK)."""

    def __init__(
        self,
        model: str = "claude-sonnet-4-20250514",
        api_key: str | None = None,
        max_tokens: int = 4096,
        system_prompt: str | None = None,
    ):
        self.model = model
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY", "")
        self.max_tokens = max_tokens
        self.system_prompt = system_prompt or SYSTEM_PROMPT
        self._client = None

    def _get_client(self):
        if self._client is None:
            try:
                import anthropic
                self._client = anthropic.Anthropic(api_key=self.api_key)
            except ImportError:
                raise AgentError(
                    "anthropic package not installed. Run: pip install anthropic"
                )
        return self._client

    def call_llm(self, system_prompt: str, user_prompt: str) -> str:
        """Send a prompt to Claude and return the raw text response.

        Public API used by both fill_hole() and LeadAgent.generate_plan().
        """
        client = self._get_client()
        try:
            message = client.messages.create(
                model=self.model,
                max_tokens=self.max_tokens,
                system=system_prompt,
                messages=[{"role": "user", "content": user_prompt}],
            )
        except Exception as e:
            raise AgentError(f"API error: {e}")
        return message.content[0].text if message.content else ""

    def fill_hole(
        self,
        hole: HoleEntry,
        context: dict[str, Any] | None = None,
    ) -> AgentResponse:
        """Send a hole to Claude and parse the response as a JSON-Patch."""
        prompt = build_prompt(hole, context)
        try:
            raw = self.call_llm(self.system_prompt, prompt)
        except AgentError as e:
            return AgentResponse(success=False, raw_response="", error=str(e))
        return _parse_patch_response(raw)


# ─────────────────────────────────────────────────────────────────────
# OpenAI agent
# ─────────────────────────────────────────────────────────────────────

class OpenAIAgent:
    """OpenAI-based agent for hole filling."""

    def __init__(
        self,
        model: str = "gpt-4o",
        api_key: str | None = None,
        max_tokens: int = 4096,
        system_prompt: str | None = None,
    ):
        self.model = model
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY", "")
        self.max_tokens = max_tokens
        self.system_prompt = system_prompt or SYSTEM_PROMPT
        self._client = None

    def _get_client(self):
        if self._client is None:
            try:
                from openai import OpenAI
                self._client = OpenAI(api_key=self.api_key)
            except ImportError:
                raise AgentError(
                    "openai package not installed. Run: pip install openai"
                )
        return self._client

    def call_llm(self, system_prompt: str, user_prompt: str) -> str:
        """Send a prompt to OpenAI and return the raw text response.

        Public API used by both fill_hole() and LeadAgent.generate_plan().
        """
        client = self._get_client()
        try:
            response = client.chat.completions.create(
                model=self.model,
                max_tokens=self.max_tokens,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
            )
        except Exception as e:
            raise AgentError(f"API error: {e}")
        return response.choices[0].message.content or "" if response.choices else ""

    def fill_hole(
        self,
        hole: HoleEntry,
        context: dict[str, Any] | None = None,
    ) -> AgentResponse:
        """Send a hole to OpenAI and parse the response as a JSON-Patch."""
        prompt = build_prompt(hole, context)
        try:
            raw = self.call_llm(self.system_prompt, prompt)
        except AgentError as e:
            return AgentResponse(success=False, raw_response="", error=str(e))
        return _parse_patch_response(raw)


# ─────────────────────────────────────────────────────────────────────
# Dry-run agent (for testing without API keys)
# ─────────────────────────────────────────────────────────────────────

class DryRunAgent:
    """Mock agent that returns a placeholder patch without calling any API."""

    def __init__(self, system_prompt: str | None = None):
        self.system_prompt = system_prompt or SYSTEM_PROMPT

    _STUB_PLAN = json.dumps({
        "modules": [{
            "name": "stub",
            "functions": [{
                "name": "stub-fn",
                "params": [{"name": "x", "type": "int"}],
                "returns": "int",
                "agent": "@stub",
                "description": "Stub function for dry-run mode",
                "contracts": {"post": "(>= result 0)"},
            }],
            "imports": [],
            "exports": ["stub-fn"],
        }],
        "metadata": {"intent": "dry-run", "version": "0.4"},
    })

    _STUB_PATCH = '[{"op": "replace", "path": "/stub", "value": {"kind": "lit-string", "value": "<stub>"}}]'

    def call_llm(self, system_prompt: str, user_prompt: str) -> str:
        """Dry-run: returns context-aware stub response.

        Returns a stub plan dict when the system prompt mentions 'plan' or
        'architecture' (Lead Agent mode), otherwise returns a stub patch array
        (hole-filling mode). Fixes Issue #1 from Language Team review.
        """
        prompt_lower = system_prompt.lower()
        if "plan" in prompt_lower or "architecture" in prompt_lower:
            return self._STUB_PLAN
        return self._STUB_PATCH

    def fill_hole(
        self,
        hole: HoleEntry,
        context: dict[str, Any] | None = None,
    ) -> AgentResponse:
        """Return a stub replace operation for the hole."""
        stub_patch = [{
            "op": "replace",
            "path": hole.pointer,
            "value": {
                "kind": "lit-string",
                "value": f"<stub: {hole.message}>",
            },
        }]
        return AgentResponse(
            success=True,
            patch_ops=stub_patch,
            raw_response=json.dumps(stub_patch),
        )

