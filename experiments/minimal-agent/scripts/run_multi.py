#!/usr/bin/env python3
"""R5-at-scale driver — Differential Implementation Pressure at corpus scale.

For each single-hole scaffold, run R independent REPEATS. Each repeat is an
isolated CELL: its own copy of the scaffold, its own `llmll checkout --multi N`
divergence session, N forced-diverse agents (claude / codex / agy) each filling
the ONE hole into its scratch, then `llmll diverge-report`. Cells are isolated
(own dir + own build output + own session sidecar) so they run concurrently.

Pipeline per cell (validated in the smoke driver):
  copy scaffold -> build .ast.json -> checkout --multi N (one per agent)
  -> each agent produces solution.llmll -> build + inject over its scratch
  -> diverge-report

Fills are pinned: diverge-report reads only the hole node from each scratch and
takes siblings/contract from the shared tree, so tampering is ignored (v0.14.9).

The aggregator reports, per hole over the R repeats: the verdict distribution
and the under-constraint-witness RATE with a Wilson 95% CI.

Modes:
  (default)       run the real agent CLIs (spends API / CLI quota)
  --mock          deterministic in-process fills, NO agent calls (plumbing)
  --prepare-only  set up one cell's dirs/sessions; do not run agents

Usage:
  run_multi.py --manifest r5-campaign/manifest.json --label scale-1 --repeats 5 --concurrency 5
  run_multi.py --manifest ... --mock --repeats 3
  run_multi.py --manifest ... --holes clamp_weak,transfer_helper --agents claude-opus-4-8,gpt-5.5

Agent cmd templating: a `{DIR}` token in an agent's `cmd` is replaced with the
absolute path of that agent's working dir (so the prompt can name an absolute
`{DIR}/AGENT_INSTRUCTIONS.md` — avoids CLIs that don't honour cwd for file search).
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


# ---------------------------------------------------------------------------
# Deterministic mock fills (no API) — validate the full pipeline end-to-end.
# Keyed by corpus file basename; enough entries for the largest N you --mock.
# ---------------------------------------------------------------------------
MOCK_FILLS = {
    # loose: divergence expected
    "clamp_weak":        ["(if (< x lo) lo x)", "lo", "(if (> x lo) x lo)"],
    "clamp_intentional": ["(if (< x lo) lo x)", "lo", "(if (> x lo) x lo)"],
    "abs_nonneg":        ["(if (< n 0) (- 0 n) n)", "0", "(if (> n 0) n 0)"],
    "range_mid":         ["lo", "hi", "lo"],
    "clamp_via_helper":  ["(maxi x lo)", "lo", "(maxi x lo)"],
    # tight: convergence expected
    "clamp_tight":       ["(- n 1)", "(+ n -1)", "(- n 1)"],
    "id_tight":          ["n", "n", "n"],
    "double_tight":      ["(+ n n)", "(+ n n)", "(+ n n)"],
    "transfer_tight":    ["(debit balance amount)", "(- balance amount)", "(debit balance amount)"],
    # loose + helper-composing
    "transfer_helper":   ["(if (>= balance amount) (debit balance amount) balance)", "balance", "0"],
}


def sh(cmd, cwd=None, timeout=None, shell=False):
    p = subprocess.run(cmd, cwd=cwd, timeout=timeout, shell=shell,
                       capture_output=True, text=True, check=False)
    return p.returncode, p.stdout, p.stderr


def build_ast(llmll, src: Path) -> Path:
    _, out, err = sh([llmll, "build", "--emit", src.name], cwd=src.parent)
    ast = src.parent / "generated" / src.stem / f"{src.stem}.ast.json"
    if not ast.exists():
        raise RuntimeError(f"build --emit failed for {src}:\n{out}\n{err}")
    return ast


def find_hole_pointer(ast_path: Path) -> str:
    d = json.loads(ast_path.read_text())
    for i, s in enumerate(d.get("statements", [])):
        b = s.get("body") if isinstance(s, dict) else None
        if isinstance(b, dict) and b.get("kind", "").startswith("hole"):
            return f"/statements/{i}/body"
    raise RuntimeError(f"no hole node found in {ast_path}")


def checkout_multi(llmll, ast_path: Path, pointer: str, n: int) -> dict:
    _, out, err = sh([llmll, "checkout", str(ast_path), "--multi", str(n), pointer])
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        raise RuntimeError(f"checkout --multi failed:\n{out}\n{err}")


def write_agent_dir(agent_dir: Path, scaffold_text: str, ctx: dict, hole_name: str):
    agent_dir.mkdir(parents=True, exist_ok=True)
    (agent_dir / "scaffold.llmll").write_text(scaffold_text)
    tok = ctx.get("token", {})
    goal = tok.get("postcondition_goal", "(unknown)")
    pre = tok.get("contract_pre", "(none)")
    scope = ", ".join(f"{s['name']}: {s['type']}" for s in tok.get("in_scope", [])
                      if isinstance(s, dict) and "name" in s)
    avail = "\n".join(
        f"    {f['name']}({', '.join(p['name'] for p in f.get('params', []))}) "
        f"-> {f.get('return_type','?')}   pre {f.get('pre','-')}   post {f.get('post','-')}"
        for f in tok.get("available_functions", []) if isinstance(f, dict))
    instr = f"""# Task — fill ONE hole in an LLMLL program

`scaffold.llmll` in this directory is a complete LLMLL program with exactly one
hole marked `?hole`. Replace `?hole` with a correct implementation.

Hole: `{hole_name}`
  parameters in scope: {scope}
  precondition (assumed true): {pre}
  postcondition you MUST satisfy: {goal}

Sibling functions you MAY call (already verified — use their contracts):
{avail if avail.strip() else "    (none)"}

Rules:
- Change ONLY the `?hole` expression. Do NOT change the contract (pre/post), the
  signature, or any sibling definition.
- The body must type-check and satisfy the postcondition.
- Write the COMPLETE resulting program (scaffold with `?hole` replaced) to a new
  file `solution.llmll` in this directory. Output nothing else.

`llmll verify solution.llmll` checks your work (SAFE = postcondition proven).
"""
    (agent_dir / "AGENT_INSTRUCTIONS.md").write_text(instr)


def apply_mock(agent_dir: Path, scaffold_text: str, fill_body: str):
    (agent_dir / "solution.llmll").write_text(scaffold_text.replace("?hole", fill_body))


def inject(llmll, solution: Path, scratch: str):
    ast = build_ast(llmll, solution)
    shutil.copyfile(ast, scratch)


def diverge_report(llmll, ast_path: Path, session: str) -> dict:
    _, out, err = sh([llmll, "diverge-report", str(ast_path), session])
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        raise RuntimeError(f"diverge-report failed:\n{out}\n{err}")


def run_cell(hole, agents, cell_dir: Path, llmll, timeout, mock, prepare_only) -> dict:
    """One isolated (hole, repeat) cell: own scaffold copy, session, agents."""
    name = hole["name"]
    corpus_src = Path(hole["src"]).resolve()
    n = len(agents)
    cell_dir.mkdir(parents=True, exist_ok=True)

    # Isolated copy of the scaffold; build + session live entirely in cell_dir.
    local_src = cell_dir / corpus_src.name
    scaffold_text = corpus_src.read_text()
    local_src.write_text(scaffold_text)
    shared_ast = build_ast(llmll, local_src)
    pointer = hole.get("pointer") or find_hole_pointer(shared_ast)

    session = None
    slots = []
    for i, agent in enumerate(agents):
        ctx = checkout_multi(llmll, shared_ast, pointer, n)
        session = session or ctx["session"]
        adir = cell_dir / f"slot{i+1}-{agent['name']}"
        write_agent_dir(adir, scaffold_text, ctx, name)
        slots.append({"agent": agent, "dir": adir, "scratch": ctx["scratch"]})

    if prepare_only:
        return {"hole": name, "pointer": pointer, "session": session,
                "prepared": [str(s["dir"]) for s in slots]}

    fill_log = []
    for i, slot in enumerate(slots):
        adir, agent = slot["dir"], slot["agent"]
        sol = adir / "solution.llmll"
        if mock:
            fills = MOCK_FILLS.get(corpus_src.stem, ["?hole"])
            apply_mock(adir, scaffold_text, fills[min(i, len(fills) - 1)])
            status = "mock"
        else:
            cmd = agent["cmd"].replace("{DIR}", str(adir.resolve()))
            try:
                rc, out, err = sh(cmd, cwd=adir, timeout=timeout, shell=True)
                status = "ran" if rc == 0 else f"exit{rc}"
            except subprocess.TimeoutExpired:
                out, err, status = "", "TIMEOUT", "timeout"
            (adir / "agent.stdout.log").write_text(out)
            (adir / "agent.stderr.log").write_text(err)
        if not sol.exists():
            fill_log.append({"agent": agent["name"], "status": status, "fill": None})
            continue
        try:
            inject(llmll, sol, slot["scratch"])
            fill_log.append({"agent": agent["name"], "status": status, "fill": "injected"})
        except Exception as e:  # noqa: BLE001
            fill_log.append({"agent": agent["name"], "status": status, "fill": f"build-fail: {e}"})

    assert session is not None
    report = diverge_report(llmll, shared_ast, session)
    dw = report.get("divergence_witness", {})
    result = {
        "hole": name, "pointer": pointer, "session": session, "n_agents": n,
        "fills": fill_log, "verdict": dw.get("verdict"),
        "status_partition": dw.get("status_partition"),
        "distinguishing_witness": dw.get("distinguishing_witness"),
    }
    (cell_dir / "diverge_report.json").write_text(json.dumps(report, indent=2))
    (cell_dir / "result.json").write_text(json.dumps(result, indent=2))
    return result


def wilson(k: int, n: int, z: float = 1.96):
    """Wilson score 95% CI for a binomial proportion."""
    if n == 0:
        return (0.0, 0.0, 0.0)
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = (z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / denom
    return (round(p, 3), round(max(0.0, center - half), 3), round(min(1.0, center + half), 3))


def aggregate(hole_names, cells_by_hole):
    """Per-hole verdict distribution + under-constraint-witness rate (Wilson CI)."""
    agg = {}
    for h in hole_names:
        cells = cells_by_hole.get(h, [])
        r = len(cells)
        dist = {}
        for c in cells:
            dist[c.get("verdict")] = dist.get(c.get("verdict"), 0) + 1
        wk = dist.get("under-constraint-witness", 0)
        # count cells where a witness was OBSERVED (incl. suppressed-intentional)
        observed = wk + dist.get("suppressed-intentional", 0)
        agg[h] = {
            "repeats": r,
            "verdicts": dist,
            "witness_rate": wilson(wk, r),
            "divergence_observed_rate": wilson(observed, r),
        }
    return agg


def main() -> int:
    ap = argparse.ArgumentParser(description="R5-at-scale differential-pressure driver.")
    ap.add_argument("--manifest", required=True, type=Path)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--label", default="run")
    ap.add_argument("--repeats", type=int, default=1, help="Independent runs per hole.")
    ap.add_argument("--concurrency", type=int, default=1, help="Max cells running at once.")
    ap.add_argument("--holes", default=None, help="Comma-separated hole names (default: all).")
    ap.add_argument("--agents", default=None, help="Comma-separated agent names (default: all).")
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--prepare-only", action="store_true")
    args = ap.parse_args()

    man = json.loads(args.manifest.read_text())
    llmll = man.get("llmll_cmd", "llmll")
    timeout = man.get("timeout_seconds", 1800)
    mroot = args.manifest.resolve().parent

    agents = man["agents"]
    if args.agents:
        want = set(args.agents.split(","))
        agents = [a for a in agents if a["name"] in want]
    holes = man["holes"]
    if args.holes:
        want = set(args.holes.split(","))
        holes = [h for h in holes if h["name"] in want]
    for h in holes:
        if not Path(h["src"]).is_absolute():
            h["src"] = str((mroot / h["src"]).resolve())

    out_root = (args.out or (mroot / "runs")) / args.label
    out_root.mkdir(parents=True, exist_ok=True)

    mode = "MOCK" if args.mock else ("PREPARE-ONLY" if args.prepare_only else "LIVE")
    reps = 1 if args.prepare_only else args.repeats
    print(f"R5-at-scale [{mode}] — {len(holes)} holes x {len(agents)} agents x {reps} reps "
          f"= {len(holes)*reps} cells, concurrency={args.concurrency}", file=sys.stderr)

    # Build the cell work-list: (hole, repeat) -> isolated dir.
    tasks = []
    for h in holes:
        for k in range(reps):
            cell_dir = out_root / h["name"] / f"rep{k+1}"
            tasks.append((h, cell_dir))

    lock = threading.Lock()
    cells_by_hole = {h["name"]: [] for h in holes}
    done = [0]

    def work(item):
        h, cell_dir = item
        try:
            return h["name"], run_cell(h, agents, cell_dir, llmll, timeout, args.mock, args.prepare_only)
        except Exception as e:  # noqa: BLE001
            return h["name"], {"hole": h["name"], "error": str(e)}

    with ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as ex:
        futs = [ex.submit(work, t) for t in tasks]
        for fut in as_completed(futs):
            hname, res = fut.result()
            with lock:
                cells_by_hole[hname].append(res)
                done[0] += 1
                v = res.get("verdict", res.get("error", "?"))
                sp = res.get("status_partition") or {}
                print(f"  [{done[0]}/{len(tasks)}] {hname:<20} {str(v):<26} "
                      f"v={len(sp.get('verified',[]))} te={len(sp.get('type_error',[]))} "
                      f"rf={len(sp.get('refuted',[]))}", file=sys.stderr)

    summary = {"mode": mode, "repeats": reps, "n_holes": len(holes),
               "agents": [a["name"] for a in agents],
               "aggregate": None if args.prepare_only else aggregate([h["name"] for h in holes], cells_by_hole),
               "cells": cells_by_hole}
    (out_root / "matrix.json").write_text(json.dumps(summary, indent=2))

    if not args.prepare_only:
        print("\n=== per-hole aggregate (witness rate, Wilson 95% CI) ===", file=sys.stderr)
        for h in holes:
            a = summary["aggregate"][h["name"]]
            p, lo, hi = a["witness_rate"]
            print(f"  {h['name']:<20} witness {p:.2f} [{lo:.2f},{hi:.2f}]  "
                  f"verdicts={a['verdicts']}", file=sys.stderr)
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
