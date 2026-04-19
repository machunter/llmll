"""
compiler.py — Subprocess wrapper for the LLMLL compiler CLI.

All compiler interactions go through this module: holes, checkout, patch.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class HoleDep:
    """One dependency edge."""
    pointer: str
    via: str
    reason: str


@dataclass
class HoleEntry:
    """One hole as reported by `llmll holes --json --deps`."""
    pointer: str
    kind: str
    status: str
    agent: str | None
    message: str
    module_path: str
    depends_on: list[HoleDep] = field(default_factory=list)
    cycle_warning: bool = False
    inferred_type: str | None = None


@dataclass
class CheckoutToken:
    """Result of `llmll checkout`."""
    token: str
    pointer: str
    context: dict[str, Any] = field(default_factory=dict)


class CompilerError(Exception):
    """Raised when a compiler subprocess returns non-zero or malformed output."""
    def __init__(self, command: str, stderr: str, returncode: int):
        self.command = command
        self.stderr = stderr
        self.returncode = returncode
        super().__init__(f"llmll {command} failed (rc={returncode}): {stderr[:200]}")


class Compiler:
    """Thin wrapper around the llmll CLI binary."""

    def __init__(self, binary: str = "llmll", cwd: str | Path | None = None):
        self.binary = binary
        self.cwd = str(cwd) if cwd else None

    def _run(self, args: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
        cmd = [self.binary] + args
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=self.cwd,
        )
        if check and result.returncode != 0:
            raise CompilerError(
                command=" ".join(args[:2]),
                stderr=result.stderr.strip(),
                returncode=result.returncode,
            )
        return result

    # -----------------------------------------------------------------
    # holes --json --deps
    # -----------------------------------------------------------------

    def holes(self, source: str | Path) -> list[HoleEntry]:
        """Run `llmll --json holes --deps <file>` and parse the result."""
        result = self._run(["--json", "holes", "--deps", str(source)])
        raw = json.loads(result.stdout)
        entries: list[HoleEntry] = []
        for h in raw:
            deps = [
                HoleDep(pointer=d["pointer"], via=d["via"], reason=d["reason"])
                for d in h.get("depends_on", [])
            ]
            entries.append(HoleEntry(
                pointer=h["pointer"],
                kind=h.get("kind", "unknown"),
                status=h.get("status", "unknown"),
                agent=h.get("agent"),
                message=h.get("message", ""),
                module_path=h.get("module-path", ""),
                depends_on=deps,
                cycle_warning=h.get("cycle_warning", False),
                inferred_type=h.get("inferred-type"),
            ))
        return entries

    # -----------------------------------------------------------------
    # checkout
    # -----------------------------------------------------------------

    def checkout(self, source: str | Path, pointer: str) -> CheckoutToken:
        """Run `llmll checkout <file> <pointer>` and return the token."""
        result = self._run(["--json", "checkout", str(source), pointer])
        data = json.loads(result.stdout)
        return CheckoutToken(
            token=data.get("token", ""),
            pointer=pointer,
            context=data.get("context", {}),
        )

    # -----------------------------------------------------------------
    # patch
    # -----------------------------------------------------------------

    def patch(self, source: str | Path, patch_file: str | Path) -> dict[str, Any]:
        """Run `llmll patch <file> <patch.json>` and return diagnostics."""
        result = self._run(["--json", "patch", str(source), str(patch_file)], check=False)
        if result.returncode == 0:
            return {"success": True, "diagnostics": []}
        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"success": False, "diagnostics": [{"message": result.stderr.strip() or result.stdout.strip()}]}

        # Compiler returns {"result": "PatchTypeError", "diagnostics": [...]}
        # or {"result": "PatchApplyError", "message": "..."}
        # or {"result": "PatchAuthError", "message": "..."}
        if isinstance(parsed, dict):
            diags = parsed.get("diagnostics", [])
            msg = parsed.get("message", "")
            result_kind = parsed.get("result", "unknown")
            if diags:
                return {"success": False, "diagnostics": diags}
            elif msg:
                return {"success": False, "diagnostics": [{"message": f"{result_kind}: {msg}"}]}
            else:
                return {"success": False, "diagnostics": [{"message": f"{result_kind}: {json.dumps(parsed)}"}]}
        elif isinstance(parsed, list):
            return {"success": False, "diagnostics": parsed}
        else:
            return {"success": False, "diagnostics": [{"message": str(parsed)}]}

    # -----------------------------------------------------------------
    # release (abandon checkout)
    # -----------------------------------------------------------------

    def release(self, source: str | Path, pointer: str) -> None:
        """Run `llmll checkout --release <file> <pointer>`."""
        self._run(["checkout", "--release", str(source), pointer], check=False)

    # -----------------------------------------------------------------
    # spec --agent (v0.3.4)
    # -----------------------------------------------------------------

    def spec(self, *, json_output: bool = False) -> str | None:
        """Run `llmll spec` and return the agent specification.

        Returns the text output by default (for direct system prompt inclusion)
        or JSON if json_output=True.  Returns None if the compiler doesn't
        support the spec command (pre-v0.3.4 compiler).
        """
        args = ["spec"]
        if json_output:
            args.append("--json")
        try:
            result = self._run(args)
            return result.stdout
        except CompilerError:
            return None  # pre-v0.3.4 compiler; caller uses hardcoded fallback
