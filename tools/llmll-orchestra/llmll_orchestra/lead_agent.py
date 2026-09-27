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

            raw = self.agent.call_llm(system, user_prompt)

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

        Writes the plan as LLMLL S-expression source with a ?delegate hole for
        each function body, then has the compiler emit the JSON-AST
        (`llmll build --emit`). The compiler owns the document shape, so the
        skeleton cannot drift from the schema the way a hand-built dict did:
        this module used to write `def-logic`, `{"kind": "int"}` and a `type`
        key the reader ignores, and the result did not even parse.

        Returns the path to the emitted `.ast.json`.
        Raises ValueError, with the compiler's output, if the source does not
        emit or the emitted document does not pass `llmll check`. Delegate
        holes type-check, so a failure here is a real defect in the plan.
        """
        self._log("Generating skeleton from plan")
        source = _plan_to_source(plan)

        workdir = Path(tempfile.mkdtemp(prefix="llmll-skeleton-"))
        src_path = workdir / "skeleton.llmll"
        src_path.write_text(source, encoding="utf-8")
        out_dir = workdir / "out"

        emit = self.compiler._run(
            ["build", str(src_path), "--emit", "-o", str(out_dir)], check=False
        )
        skeleton_path = out_dir / "skeleton.ast.json"
        if emit.returncode != 0 or not skeleton_path.exists():
            raise ValueError(
                f"Skeleton source did not emit ({src_path}):\n"
                f"{emit.stdout}{emit.stderr}"
            )

        check = self.compiler._run(
            ["--json", "check", str(skeleton_path)], check=False
        )
        if check.returncode != 0:
            raise ValueError(
                f"Skeleton does not type-check ({skeleton_path}):\n"
                f"{check.stdout}{check.stderr}"
            )

        self._log(f"Skeleton written to {skeleton_path}")
        return str(skeleton_path)


# ─────────────────────────────────────────────────────────────────────
# Plan -> LLMLL source
# ─────────────────────────────────────────────────────────────────────

# Capability named by each WASI import path.
_WASI_CAPABILITY = {"wasi.io": "stdout", "wasi.fs": "filesystem", "wasi.http": "http"}


def _plan_to_source(plan: dict) -> str:
    """Convert a plan dict to LLMLL S-expression source.

    Plan types and contract expressions are LLMLL surface syntax already, so
    they pass through verbatim and the compiler's parser judges them. Every
    function is a `def-shell` whose body is `?delegate`: a filled body may call
    its siblings, which a strict `def` may not.
    """
    lines: list[str] = []
    for module in plan.get("modules", []):
        for imp in module.get("imports", []):
            if imp.startswith("wasi."):
                cap = _WASI_CAPABILITY.get(imp, imp.split(".")[-1])
                lines.append(f"(import {imp} (capability {cap} :deterministic false))")
            else:
                lines.append(f"(import {imp})")

        exports = module.get("exports", [])
        if exports:
            lines.append(f"(export {' '.join(exports)})")

        for fn in module.get("functions", []):
            params = " ".join(f"{p['name']}: {p['type']}" for p in fn.get("params", []))
            ret = fn.get("returns")
            head = f"(def-shell {fn['name']} [{params}]" + (f" -> {ret}" if ret else "")
            lines.append(head)
            contracts = fn.get("contracts") or {}
            for side in ("pre", "post"):
                if contracts.get(side):
                    lines.append(f"  ({side} {contracts[side]})")
            agent = fn.get("agent", "@agent")
            desc = _sexpr_string(fn.get("description", f"Implement {fn['name']}"))
            hole = f"?delegate {agent} {desc}" + (f" -> {ret}" if ret else "")
            lines.append(f"  ({hole}))")
    return "\n".join(lines) + "\n"


def _sexpr_string(text: str) -> str:
    """Quote text as an LLMLL string literal on one line."""
    one_line = " ".join(str(text).split())
    return '"' + one_line.replace("\\", "\\\\").replace('"', '\\"') + '"'


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
