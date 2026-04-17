"""
__main__.py — CLI entry point for llmll-orchestra.

Usage:
    llmll-orchestra <source.ast.json> [options]
    python -m llmll_orchestra <source.ast.json> [options]
"""

from __future__ import annotations

import argparse
import json
import sys

from .compiler import Compiler
from .agent import Agent, OpenAIAgent, DryRunAgent
from .orchestrator import Orchestrator


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="llmll-orchestra",
        description="Multi-agent orchestrator for LLMLL hole-filling",
    )
    parser.add_argument(
        "source",
        help="Path to .llmll or .ast.json source file",
    )
    parser.add_argument(
        "--llmll",
        default="llmll",
        help="Path to the llmll compiler binary (default: llmll)",
    )
    parser.add_argument(
        "--provider",
        choices=["anthropic", "openai"],
        default="openai",
        help="LLM provider (default: openai)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Model name (default: gpt-4o for openai, claude-sonnet-4-20250514 for anthropic)",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=3,
        help="Max retry attempts per hole (default: 3)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Use stub agent (no API calls) — for CI and testing",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output results as JSON",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print detailed progress to stderr",
    )
    parser.add_argument(
        "--scan-only",
        action="store_true",
        help="Only scan and display holes with scheduling tiers, don't fill",
    )

    args = parser.parse_args(argv)

    # Set up components
    compiler = Compiler(binary=args.llmll)

    if args.dry_run:
        agent = DryRunAgent()
    elif args.provider == "openai":
        model = args.model or "gpt-4o"
        agent = OpenAIAgent(model=model)
    else:
        model = args.model or "claude-sonnet-4-20250514"
        agent = Agent(model=model)

    orchestrator = Orchestrator(
        compiler=compiler,
        agent=agent,
        max_retries=args.max_retries,
        verbose=args.verbose,
    )

    # Scan-only mode: just show the dependency graph and scheduling
    if args.scan_only:
        return _scan_only(compiler, args)

    # Full run
    report = orchestrator.run(args.source)

    if args.json_output:
        print(json.dumps(report.to_dict(), indent=2))
    else:
        _print_report(report)

    return 0 if report.failed == 0 else 1


def _scan_only(compiler: Compiler, args) -> int:
    """Display holes and scheduling tiers without filling."""
    from .graph import scheduling_tiers

    try:
        holes = compiler.holes(args.source)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    fillable = [h for h in holes if h.status in ("agent-task", "blocking")]
    tiers = scheduling_tiers(fillable)

    if args.json_output:
        data = {
            "source": args.source,
            "total_holes": len(holes),
            "fillable": len(fillable),
            "tiers": [
                [{"pointer": h.pointer, "agent": h.agent, "kind": h.kind}
                 for h in tier]
                for tier in tiers
            ],
        }
        print(json.dumps(data, indent=2))
    else:
        print(f"{args.source} — {len(holes)} holes ({len(fillable)} fillable)")
        print()
        for i, tier in enumerate(tiers):
            print(f"  Tier {i} (parallel):")
            for h in tier:
                agent_tag = f" [{h.agent}]" if h.agent else ""
                cycle_tag = " ⚠ cycle" if h.cycle_warning else ""
                deps = ", ".join(d.via for d in h.depends_on)
                dep_tag = f" ← depends on: {deps}" if deps else ""
                print(f"    {h.pointer}{agent_tag}{cycle_tag}{dep_tag}")
        print()

    return 0


def _print_report(report) -> None:
    """Print human-readable orchestration report."""
    print(f"\n{'═' * 60}")
    print(f"  llmll-orchestra report: {report.source_file}")
    print(f"{'═' * 60}")
    print(f"  Total holes:  {report.total_holes}")
    print(f"  Filled:       {report.filled}")
    print(f"  Failed:       {report.failed}")
    print(f"  Skipped:      {report.skipped}")
    print(f"{'─' * 60}")

    for r in report.results:
        status = "✅" if r.success else "❌"
        agent_tag = f" [{r.agent}]" if r.agent else ""
        print(f"  {status} {r.pointer}{agent_tag}  ({r.attempts} attempts)")
        if r.error:
            print(f"     └─ {r.error}")

    print(f"{'═' * 60}\n")


if __name__ == "__main__":
    sys.exit(main())
