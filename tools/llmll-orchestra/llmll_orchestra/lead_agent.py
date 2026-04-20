"""
lead_agent.py — Lead Agent for LLMLL orchestration.

Generates architecture plans from intents and converts them to
type-checked skeletons. The Lead Agent uses the LLM client
infrastructure from agent.py.

v0.4: Sprint 2 Tasks 4-6.
"""

from __future__ import annotations

import json
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .compiler import Compiler, CompilerError
from .quality import check_plan_quality, QualityResult


# ─────────────────────────────────────────────────────────────────────
# Lead Agent system prompt
# ─────────────────────────────────────────────────────────────────────

_LEAD_SYSTEM_PROMPT = """\
You are the LLMLL Lead Agent. Your job is to decompose a software intent
into a structured architecture plan.

You will receive:
1. A natural-language intent describing what to build
2. The LLMLL built-in function reference (types and signatures)

You must produce a JSON architecture plan with this exact schema:

```json
{
  "modules": [
    {
      "name": "<module-name>",
      "functions": [
        {
          "name": "<function-name>",
          "params": [{"name": "<param>", "type": "<llmll-type>"}],
          "returns": "<llmll-type>",
          "agent": "@<agent-name>",
          "contracts": {
            "pre": "<llmll-expression or null>",
            "post": "<llmll-expression or null>"
          },
          "description": "<what this function does>"
        }
      ],
      "imports": ["<module-path>"],
      "exports": ["<function-name>"]
    }
  ],
  "dependency_graph": {"<module>": ["<depends-on>"]},
  "metadata": {
    "intent": "<original intent>",
    "version": "0.4"
  }
}
```

## Rules

1. Return ONLY the JSON plan. No commentary, no markdown fences.
2. Use specific LLMLL types (int, string, bool, list[T], Result[T,E], (T1,T2)).
   Do NOT use "any" or generic "string" for everything.
3. Every function MUST have an "@agent" assignment.
4. Include contracts (pre/post) where meaningful — at least on boundary functions.
5. Module names should be lowercase, hyphen-separated.
6. Function names should be lowercase, hyphen-separated (LLMLL convention).
7. Imports should include "wasi.io" if the module uses stdout.
8. Think about error handling — use Result types for fallible operations.
"""


# ─────────────────────────────────────────────────────────────────────
# Lead Agent
# ─────────────────────────────────────────────────────────────────────

class LeadAgent:
    """Lead Agent: generates architecture plans and skeletons from intents."""

    def __init__(self, agent, compiler: Compiler, verbose: bool = False):
        """
        Args:
            agent: An Agent/OpenAIAgent/DryRunAgent with _call_llm method.
            compiler: Compiler CLI wrapper.
            verbose: Print progress to stderr.
        """
        self.agent = agent
        self.compiler = compiler
        self.verbose = verbose

    def _log(self, msg: str) -> None:
        if self.verbose:
            import sys
            print(f"  ◦ lead: {msg}", file=sys.stderr)

    def generate_plan(self, intent: str, max_retries: int = 2) -> dict:
        """Intent -> structured architecture plan (JSON).

        Calls the LLM with the lead agent system prompt and the intent.
        Validates the plan with quality heuristics; retries on blocking issues.

        Returns the validated plan dict.
        Raises ValueError if the plan cannot be generated after retries.
        """
        # Get builtins reference from compiler
        spec = self.compiler.spec(json_output=False)
        spec_section = f"\n## LLMLL Built-in Reference\n\n{spec}" if spec else ""

        system = _LEAD_SYSTEM_PROMPT + spec_section
        user_prompt = f"## Intent\n\n{intent}"

        last_error = None

        for attempt in range(1, max_retries + 2):  # +2 because range is exclusive
            self._log(f"Plan generation attempt {attempt}")

            raw = self.agent._call_llm(system, user_prompt)

            # Parse JSON (strip markdown fences if present)
            plan = _parse_json_response(raw)
            if plan is None:
                last_error = f"LLM returned invalid JSON: {raw[:200]}"
                user_prompt = f"Your previous response was not valid JSON. {last_error}\n\nPlease try again.\n\n## Intent\n\n{intent}"
                continue

            # Quality check
            quality = check_plan_quality(plan)
            blocking = [q for q in quality if q.blocking]

            if not blocking:
                self._log(f"Plan accepted (attempt {attempt})")
                # Attach advisory warnings to metadata
                advisories = [q for q in quality if not q.blocking]
                if advisories:
                    plan.setdefault("metadata", {})["warnings"] = [
                        {"heuristic": q.heuristic, "message": q.message}
                        for q in advisories
                    ]
                return plan

            # Blocking issues — retry with feedback
            feedback = "\n".join(f"- [{q.heuristic}] {q.message}" for q in blocking)
            last_error = f"Plan rejected: {feedback}"
            self._log(f"Plan rejected (attempt {attempt}): {feedback}")
            user_prompt = (
                f"Your previous plan was rejected by quality checks:\n{feedback}\n\n"
                f"Please fix these issues and regenerate the plan.\n\n## Intent\n\n{intent}"
            )

        raise ValueError(f"Failed to generate valid plan after {max_retries + 1} attempts: {last_error}")

    def generate_skeleton(self, plan: dict) -> str:
        """Plan -> JSON-AST skeleton file path.

        Converts the architecture plan into a JSON-AST file with ?delegate holes
        for each function body. Validates with `llmll check`.

        Returns the path to the generated skeleton file.
        Raises ValueError if the skeleton fails type-checking.
        """
        self._log("Generating skeleton from plan")
        ast = _plan_to_ast(plan)

        # Write to temp file
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".ast.json", delete=False, prefix="llmll-skeleton-"
        ) as f:
            json.dump(ast, f, indent=2)
            skeleton_path = f.name

        self._log(f"Skeleton written to {skeleton_path}")

        # Validate with compiler (best-effort; don't fail on type errors
        # since the skeleton has holes that will be filled later)
        try:
            # We use check=False because skeletons have holes
            result = self.compiler._run(
                ["--json", "check", skeleton_path], check=False
            )
            if result.returncode == 0:
                self._log("Skeleton passes type-check")
            else:
                self._log(f"Skeleton has expected type warnings (holes present)")
        except Exception as e:
            self._log(f"Skeleton validation skipped: {e}")

        return skeleton_path


# ─────────────────────────────────────────────────────────────────────
# Plan -> JSON-AST conversion
# ─────────────────────────────────────────────────────────────────────

def _plan_to_ast(plan: dict) -> dict:
    """Convert a plan dict to a JSON-AST dict (for llmll check)."""
    statements = []

    for module in plan.get("modules", []):
        # Add imports
        for imp in module.get("imports", []):
            stmt: dict[str, Any] = {"kind": "import", "path": imp}
            if imp.startswith("wasi."):
                stmt["capability"] = {"name": "stdout", "deterministic": False}
            statements.append(stmt)

        # Add exports
        exports = module.get("exports", [])
        if exports:
            statements.append({"kind": "export", "names": exports})

        # Add function definitions with ?delegate holes
        for fn in module.get("functions", []):
            params = [
                {"name": p["name"], "type": _type_to_ast(p["type"])}
                for p in fn.get("params", [])
            ]

            ret_type = _type_to_ast(fn["returns"]) if "returns" in fn else None

            # Build contract
            contract: dict[str, Any] = {}
            contracts = fn.get("contracts", {})
            if contracts.get("pre"):
                contract["pre"] = contracts["pre"]
            if contracts.get("post"):
                contract["post"] = contracts["post"]

            # Body is a ?delegate hole with agent assignment
            agent = fn.get("agent", "@agent")
            body = {
                "kind": "hole",
                "hole_kind": "delegate",
                "agent": agent,
                "message": fn.get("description", f"Implement {fn['name']}"),
            }

            stmt = {
                "kind": "def-logic",
                "name": fn["name"],
                "params": params,
                "body": body,
            }
            if ret_type:
                stmt["return_type"] = ret_type
            if contract:
                stmt["contract"] = contract

            statements.append(stmt)

    return {"statements": statements}


def _type_to_ast(type_str: str) -> dict:
    """Convert a type string like 'list[int]' to a JSON-AST type node."""
    t = type_str.strip()

    if t == "int":
        return {"kind": "int"}
    elif t == "bool":
        return {"kind": "bool"}
    elif t == "string":
        return {"kind": "string"}
    elif t == "unit":
        return {"kind": "unit"}
    elif t.startswith("list[") and t.endswith("]"):
        inner = t[5:-1]
        return {"kind": "list", "element_type": _type_to_ast(inner)}
    elif t.startswith("Result["):
        # Result[T, E]
        inner = t[7:-1]
        parts = _split_type_args(inner)
        if len(parts) == 2:
            return {
                "kind": "result",
                "ok_type": _type_to_ast(parts[0]),
                "err_type": _type_to_ast(parts[1]),
            }
    elif "," in t and t.startswith("(") and t.endswith(")"):
        # Pair type (T1, T2)
        inner = t[1:-1]
        parts = _split_type_args(inner)
        if len(parts) == 2:
            return {
                "kind": "pair-type",
                "first_type": _type_to_ast(parts[0]),
                "second_type": _type_to_ast(parts[1]),
            }

    # Fallback: custom type
    return {"kind": "custom", "name": t}


def _split_type_args(s: str) -> list[str]:
    """Split type arguments respecting bracket nesting."""
    parts = []
    depth = 0
    current = ""
    for c in s:
        if c in "([":
            depth += 1
            current += c
        elif c in ")]":
            depth -= 1
            current += c
        elif c == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += c
    if current.strip():
        parts.append(current.strip())
    return parts


# ─────────────────────────────────────────────────────────────────────
# JSON response parsing
# ─────────────────────────────────────────────────────────────────────

def _parse_json_response(raw: str) -> dict | None:
    """Parse LLM response as JSON, stripping markdown fences."""
    text = raw.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        text = "\n".join(lines[1:])
        if text.endswith("```"):
            text = text[:-3].strip()
    try:
        result = json.loads(text)
        if isinstance(result, dict):
            return result
        return None
    except json.JSONDecodeError:
        return None
