"""
orchestrator.py — Main hole-filling loop.

Coordinates the compiler, dependency graph, and agent to fill holes
in topological order with retry on failure.
"""

from __future__ import annotations

import json
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

from .compiler import Compiler, CompilerError, HoleEntry
from .graph import topo_sort, scheduling_tiers
from .agent import build_system_prompt


# ─────────────────────────────────────────────────────────────────────
# Result types
# ─────────────────────────────────────────────────────────────────────

@dataclass
class HoleResult:
    """Outcome of attempting to fill one hole."""
    pointer: str
    agent: str | None
    attempts: int
    success: bool
    error: str | None = None
    patch_ops: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class OrchestratorReport:
    """Summary of a full orchestration run."""
    source_file: str
    total_holes: int
    filled: int
    failed: int
    skipped: int
    results: list[HoleResult] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_file": self.source_file,
            "total_holes": self.total_holes,
            "filled": self.filled,
            "failed": self.failed,
            "skipped": self.skipped,
            "results": [
                {
                    "pointer": r.pointer,
                    "agent": r.agent,
                    "attempts": r.attempts,
                    "success": r.success,
                    "error": r.error,
                }
                for r in self.results
            ],
        }


# ─────────────────────────────────────────────────────────────────────
# Agent protocol (for type-checking against Agent / DryRunAgent)
# ─────────────────────────────────────────────────────────────────────

class AgentProtocol(Protocol):
    system_prompt: str
    def fill_hole(
        self, hole: HoleEntry, context: dict[str, Any] | None = None
    ) -> Any: ...


# ─────────────────────────────────────────────────────────────────────
# Orchestrator
# ─────────────────────────────────────────────────────────────────────

class Orchestrator:
    """
    Fills holes in a LLMLL source file using the compiler CLI and an LLM agent.

    Workflow per hole:
      1. `llmll checkout <file> <pointer>` → lock + context
      2. agent.fill_hole(hole, context) → JSON-Patch ops
      3. Write patch to temp file
      4. `llmll patch <file> <patch.json>` → apply + re-verify
      5. On failure: feed diagnostics back to agent, retry (max_retries)
      6. On terminal failure: `llmll checkout --release` and record error
    """

    def __init__(
        self,
        compiler: Compiler,
        agent: AgentProtocol,
        max_retries: int = 3,
        verbose: bool = False,
    ):
        self.compiler = compiler
        self.agent = agent
        self.max_retries = max_retries
        self.verbose = verbose

    def _log(self, msg: str) -> None:
        if self.verbose:
            print(f"  ◦ {msg}", file=sys.stderr)

    def run(self, source: str | Path) -> OrchestratorReport:
        """Execute the full orchestration loop on a source file."""
        source = str(source)

        # Step 0: Fetch compiler spec for dynamic system prompt (v0.3.4)
        self._log("Fetching compiler spec")
        compiler_spec = self.compiler.spec()
        if compiler_spec:
            self._log(f"Using compiler-emitted spec ({len(compiler_spec)} chars)")
            self.agent.system_prompt = build_system_prompt(compiler_spec)
        else:
            self._log("Compiler spec unavailable, using legacy prompt")

        # Step 1: Get all holes with dependency graph
        self._log(f"Scanning holes in {source}")
        try:
            holes = self.compiler.holes(source)
        except CompilerError as e:
            return OrchestratorReport(
                source_file=source,
                total_holes=0,
                filled=0,
                failed=0,
                skipped=0,
                results=[HoleResult(
                    pointer="<scan>",
                    agent=None,
                    attempts=0,
                    success=False,
                    error=str(e),
                )],
            )

        # Filter to fillable holes (agent-task or blocking, not proof-required)
        fillable = [h for h in holes if h.status in ("agent-task", "blocking")]
        self._log(f"Found {len(holes)} holes, {len(fillable)} fillable")

        # Step 2: Topological sort
        sorted_holes = topo_sort(fillable)
        tiers = scheduling_tiers(fillable)
        self._log(f"Scheduling: {len(tiers)} tiers")
        for i, tier in enumerate(tiers):
            ptrs = [h.pointer for h in tier]
            self._log(f"  Tier {i}: {ptrs}")

        # Step 3: Fill each hole in order
        results: list[HoleResult] = []
        filled_count = 0
        failed_count = 0

        for hole in sorted_holes:
            result = self._fill_one(source, hole)
            results.append(result)
            if result.success:
                filled_count += 1
            else:
                failed_count += 1

        return OrchestratorReport(
            source_file=source,
            total_holes=len(holes),
            filled=filled_count,
            failed=failed_count,
            skipped=len(holes) - len(fillable),
            results=results,
        )

    def _fill_one(self, source: str, hole: HoleEntry) -> HoleResult:
        """Attempt to fill a single hole with retry."""
        self._log(f"Filling {hole.pointer} ({hole.agent or 'generic'})")

        # Checkout
        try:
            token = self.compiler.checkout(source, hole.pointer)
            context = token.context
        except CompilerError as e:
            self._log(f"  Checkout failed: {e}")
            return HoleResult(
                pointer=hole.pointer,
                agent=hole.agent,
                attempts=0,
                success=False,
                error=f"checkout failed: {e}",
            )

        # Retry loop
        last_error: str | None = None
        diagnostics: list[dict] = []

        for attempt in range(1, self.max_retries + 1):
            self._log(f"  Attempt {attempt}/{self.max_retries}")

            # O3: Check checkout TTL before patching
            token = self._ensure_checkout(source, hole, token)
            if token is None:
                last_error = "re-checkout failed (lock taken by another agent)"
                self._log(f"  {last_error}")
                return HoleResult(
                    pointer=hole.pointer,
                    agent=hole.agent,
                    attempts=attempt,
                    success=False,
                    error=last_error,
                )

            # O2: Build augmented context with formatted prior diagnostics
            aug_context = dict(context)
            if diagnostics:
                aug_context["prior_diagnostics"] = _format_diagnostics(diagnostics)

            # Ask the agent
            response = self.agent.fill_hole(hole, aug_context)
            if not response.success:
                last_error = response.error or "agent returned no patch"
                self._log(f"  Agent failed: {last_error}")
                continue

            # Write patch to temp file and apply
            # Compiler expects PatchRequest: {"token": "...", "patch": [...]}
            try:
                patch_request = {
                    # EC-6: always use the current token (may have been re-issued
                    # by _ensure_checkout after TTL expiry)
                    "token": token.token,
                    "patch": response.patch_ops,
                }
                with tempfile.NamedTemporaryFile(
                    mode="w", suffix=".json", delete=False
                ) as f:
                    json.dump(patch_request, f)
                    patch_path = f.name

                result = self.compiler.patch(source, patch_path)

                if result["success"]:
                    self._log(f"  ✅ Filled {hole.pointer}")
                    return HoleResult(
                        pointer=hole.pointer,
                        agent=hole.agent,
                        attempts=attempt,
                        success=True,
                        patch_ops=response.patch_ops,
                    )
                else:
                    diagnostics = result.get("diagnostics", [])
                    last_error = "; ".join(
                        d.get("message", "unknown") if isinstance(d, dict) else str(d)
                        for d in diagnostics
                    )
                    self._log(f"  Patch rejected: {last_error}")

            except (CompilerError, OSError) as e:
                last_error = str(e)
                self._log(f"  Patch error: {last_error}")

            finally:
                # Clean up temp file
                try:
                    Path(patch_path).unlink(missing_ok=True)
                except Exception:
                    pass

        # All retries exhausted — release the checkout
        self._log(f"  ❌ Failed after {self.max_retries} attempts")
        self.compiler.release(source, hole.pointer)

        return HoleResult(
            pointer=hole.pointer,
            agent=hole.agent,
            attempts=self.max_retries,
            success=False,
            error=last_error,
        )

    def _ensure_checkout(
        self, source: str, hole: HoleEntry, token: CheckoutToken
    ) -> CheckoutToken | None:
        """O3: Check checkout TTL; re-checkout if expired.

        EC-6: If a re-checkout is necessary, the new token is returned.
        The caller MUST use this updated token in subsequent patch requests.

        Returns None if the lock is taken by another agent.
        """
        try:
            status = self.compiler.checkout_status(source, token.token)
            if status.get("remaining_seconds", 0) > 5:
                return token  # plenty of time
            # TTL expired or about to expire — re-checkout
            self._log(f"  Checkout TTL low/expired, re-checking out {hole.pointer}")
        except CompilerError:
            # If status check fails, try re-checkout
            self._log(f"  Checkout status check failed, attempting re-checkout")

        try:
            new_token = self.compiler.checkout(source, hole.pointer)
            self._log(f"  Re-checkout succeeded (new token: {new_token.token[:8]}...)")
            return new_token
        except CompilerError as e:
            self._log(f"  Re-checkout failed: {e}")
            return None


# ─────────────────────────────────────────────────────────────────────
# O2: Diagnostic formatting for agent retry prompts
# ─────────────────────────────────────────────────────────────────────

def _format_diagnostics(diagnostics: list[dict]) -> str:
    """Format raw diagnostics into human-readable text for agent retry prompts.

    Language Team rule: don't pass raw JSON blobs to the agent.
    Format them as actionable error messages instead.
    """
    if not diagnostics:
        return "No specific diagnostics."

    lines = ["Your previous attempt was rejected by the compiler:\n"]
    for i, d in enumerate(diagnostics, 1):
        if isinstance(d, dict):
            kind = d.get("kind", "error")
            msg = d.get("message", "unknown error")
            pointer = d.get("pointer", "")
            expected = d.get("expected", "")
            got = d.get("got", "")
            suggestion = d.get("suggestion", "")

            line = f"  {i}. [{kind}] {msg}"
            if pointer:
                line += f"\n     At: {pointer}"
            if expected and got:
                line += f"\n     Expected: {expected}, Got: {got}"
            if suggestion:
                line += f"\n     Suggestion: {suggestion}"
            lines.append(line)
        else:
            lines.append(f"  {i}. {d}")

    lines.append("\nPlease fix these issues in your next attempt.")
    return "\n".join(lines)
