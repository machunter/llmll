#!/usr/bin/env python3
"""R5-at-scale driver — Differential Implementation Pressure at corpus scale.

For each single-hole scaffold in a corpus, open an `llmll checkout --multi N`
divergence session, have N *forced-diverse* agents each fill that ONE hole into
its isolated scratch copy, then `llmll diverge-report` classifies observational
divergence over the probe set Omega among the fills that all verify.

This is the campaign extension of the plumbing validated in the smoke driver:
  checkout --multi  ->  inject each agent's fill over its scratch  ->  diverge-report
The only added step over the smoke test is that fills are PRODUCED by live agents
(claude / codex / agy) rather than read off disk.

Fills are produced as complete `.llmll` programs (scaffold with the hole filled),
built to `.ast.json`, and copied over the agent's scratch slot. `diverge-report`
reads only the hole node from each scratch and pins siblings/contract to the
shared (trusted) tree, so a fill that tampers with a sibling or the contract is
ignored — only the hole body counts (v0.14.9 sibling-call classification).

Modes:
  (default)       run the real agent CLIs (spends API / CLI quota)
  --mock          deterministic in-process fills, NO agent calls (plumbing check)
  --prepare-only  set up per-agent dirs + sessions, do not run agents

Usage:
  run_multi.py --manifest r5-campaign/manifest.json --out r5-campaign/runs [--mock]
  run_multi.py --manifest ... --holes clamp_weak,transfer_helper --agents claude-opus-4-8
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Deterministic mock fills (no API) — validate the full pipeline end-to-end.
# Keyed by corpus file basename. Each list is the fill BODY per slot; enough
# entries for the largest N you run in --mock (extra slots reuse the last).
# ---------------------------------------------------------------------------
MOCK_FILLS = {
    # weak post (>= result lo): clamp vs constant -> divergence
    "clamp_weak":        ["(if (< x lo) lo x)", "lo", "(if (> x lo) x lo)"],
    "clamp_intentional": ["(if (< x lo) lo x)", "lo", "(if (> x lo) x lo)"],
    # tight equality post: every correct fill agrees -> no divergence
    "clamp_tight":       ["(- n 1)", "(+ n -1)", "(- n 1)"],
    # helper-composing: a sibling-calling fill is now a verified competitor
    "transfer_helper":   ["(if (>= balance amount) (debit balance amount) balance)",
                          "balance", "0"],
}


def sh(cmd, cwd=None, timeout=None, shell=False):
    """Run a command, return (returncode, stdout, stderr)."""
    p = subprocess.run(
        cmd, cwd=cwd, timeout=timeout, shell=shell,
        capture_output=True, text=True, check=False,
    )
    return p.returncode, p.stdout, p.stderr


def build_ast(llmll, src: Path) -> Path:
    """`llmll build --emit <src>` -> generated/<name>/<name>.ast.json (cwd = src.parent)."""
    _, out, err = sh([llmll, "build", "--emit", src.name], cwd=src.parent)
    ast = src.parent / "generated" / src.stem / f"{src.stem}.ast.json"
    if not ast.exists():
        raise RuntimeError(f"build --emit failed for {src}:\n{out}\n{err}")
    return ast


def find_hole_pointer(ast_path: Path) -> str:
    """RFC-6901 pointer to the first body-position hole-named node."""
    d = json.loads(ast_path.read_text())
    for i, s in enumerate(d.get("statements", [])):
        b = s.get("body") if isinstance(s, dict) else None
        if isinstance(b, dict) and b.get("kind", "").startswith("hole"):
            return f"/statements/{i}/body"
    raise RuntimeError(f"no hole node found in {ast_path}")


def checkout_multi(llmll, ast_path: Path, pointer: str, n: int) -> dict:
    """One `checkout --multi N` join; returns the parsed token JSON."""
    _, out, err = sh([llmll, "checkout", str(ast_path), "--multi", str(n), pointer])
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        raise RuntimeError(f"checkout --multi failed:\n{out}\n{err}")


def write_agent_dir(agent_dir: Path, scaffold_text: str, ctx: dict, hole_name: str):
    """Prepare a per-agent working dir with the scaffold + fill instructions."""
    agent_dir.mkdir(parents=True, exist_ok=True)
    (agent_dir / "scaffold.llmll").write_text(scaffold_text)
    tok = ctx.get("token", {})
    goal = tok.get("postcondition_goal", "(unknown)")
    pre = tok.get("contract_pre", "(none)")
    scope = ", ".join(
        f"{s['name']}: {s['type']}" for s in tok.get("in_scope", [])
        if isinstance(s, dict) and "name" in s
    )
    avail = "\n".join(
        f"    {f['name']}({', '.join(p['name'] for p in f.get('params', []))}) "
        f"-> {f.get('return_type','?')}   pre {f.get('pre','-')}   post {f.get('post','-')}"
        for f in tok.get("available_functions", []) if isinstance(f, dict)
    )
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
- Do NOT change the contract (pre/post), the function signature, or any sibling
  definition. Change ONLY the `?hole` expression.
- The body must type-check and satisfy the postcondition.
- Write the COMPLETE resulting program (scaffold with `?hole` replaced) to a new
  file `solution.llmll` in this directory. Output nothing else.

You have the `llmll` compiler on PATH: `llmll verify solution.llmll` checks your
work (SAFE = the postcondition is proven).
"""
    (agent_dir / "AGENT_INSTRUCTIONS.md").write_text(instr)


def apply_mock(agent_dir: Path, scaffold_text: str, fill_body: str):
    """Write solution.llmll by substituting the mock fill body for ?hole."""
    (agent_dir / "solution.llmll").write_text(scaffold_text.replace("?hole", fill_body))


def inject(llmll, solution: Path, scratch: str):
    """Build the agent's solution and copy it over its scratch slot."""
    ast = build_ast(llmll, solution)
    shutil.copyfile(ast, scratch)


def diverge_report(llmll, ast_path: Path, session: str) -> dict:
    _, out, err = sh([llmll, "diverge-report", str(ast_path), session])
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        raise RuntimeError(f"diverge-report failed:\n{out}\n{err}")


def run_hole(hole, agents, out_root: Path, llmll, timeout, mock, prepare_only) -> dict:
    name = hole["name"]
    src = Path(hole["src"]).resolve()
    n = len(agents)
    hole_out = out_root / name
    hole_out.mkdir(parents=True, exist_ok=True)

    # Fresh shared ast + clean any prior session sidecars for this base.
    shared_ast = build_ast(llmll, src)
    base = str(shared_ast)[: -len(".ast.json")]
    for p in Path(shared_ast.parent).glob(f"{shared_ast.stem}.sess-*"):
        p.unlink()
    diverge_sidecar = Path(base + ".llmll-diverge.json")
    if diverge_sidecar.exists():
        diverge_sidecar.unlink()

    pointer = hole.get("pointer") or find_hole_pointer(shared_ast)
    scaffold_text = src.read_text()

    session = None
    slots = []
    for i, agent in enumerate(agents):
        ctx = checkout_multi(llmll, shared_ast, pointer, n)
        session = session or ctx["session"]
        scratch = ctx["scratch"]
        adir = hole_out / f"slot{i+1}-{agent['name']}"
        write_agent_dir(adir, scaffold_text, ctx, name)
        slots.append({"agent": agent, "dir": adir, "scratch": scratch, "ctx": ctx})

    if prepare_only:
        return {"hole": name, "pointer": pointer, "session": session,
                "prepared": [str(s["dir"]) for s in slots]}

    # Produce + inject each fill.
    fill_log = []
    for i, slot in enumerate(slots):
        adir, agent = slot["dir"], slot["agent"]
        sol = adir / "solution.llmll"
        if mock:
            fills = MOCK_FILLS.get(src.stem, ["?hole"])
            apply_mock(adir, scaffold_text, fills[min(i, len(fills) - 1)])
            status = "mock"
        else:
            rc, out, err = sh(agent["cmd"], cwd=adir, timeout=timeout, shell=True)
            (adir / "agent.stdout.log").write_text(out)
            (adir / "agent.stderr.log").write_text(err)
            status = "ran" if rc == 0 else f"exit{rc}"
        if not sol.exists():
            fill_log.append({"agent": agent["name"], "status": status, "fill": None})
            continue
        try:
            inject(llmll, sol, slot["scratch"])
            fill_log.append({"agent": agent["name"], "status": status, "fill": "injected"})
        except Exception as e:  # noqa: BLE001
            fill_log.append({"agent": agent["name"], "status": status, "fill": f"build-fail: {e}"})

    assert session is not None, "no divergence session was opened"
    report = diverge_report(llmll, shared_ast, session)
    dw = report.get("divergence_witness", {})
    result = {
        "hole": name, "pointer": pointer, "session": session,
        "n_agents": n, "fills": fill_log,
        "verdict": dw.get("verdict"),
        "status_partition": dw.get("status_partition"),
        "distinguishing_witness": dw.get("distinguishing_witness"),
    }
    (hole_out / "diverge_report.json").write_text(json.dumps(report, indent=2))
    (hole_out / "result.json").write_text(json.dumps(result, indent=2))
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description="R5-at-scale differential-pressure driver.")
    ap.add_argument("--manifest", required=True, type=Path)
    ap.add_argument("--out", type=Path, default=None, help="Output root (default: <manifest dir>/runs/<label>).")
    ap.add_argument("--label", default="run", help="Run label (subdir under --out).")
    ap.add_argument("--holes", default=None, help="Comma-separated hole names to include (default: all).")
    ap.add_argument("--agents", default=None, help="Comma-separated agent names to include (default: all).")
    ap.add_argument("--mock", action="store_true", help="Deterministic in-process fills, no agent calls.")
    ap.add_argument("--prepare-only", action="store_true", help="Set up dirs/sessions; do not run agents.")
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
    # Resolve hole src relative to the manifest dir.
    for h in holes:
        if not Path(h["src"]).is_absolute():
            h["src"] = str((mroot / h["src"]).resolve())

    out_root = (args.out or (mroot / "runs")) / args.label
    out_root.mkdir(parents=True, exist_ok=True)

    mode = "MOCK" if args.mock else ("PREPARE-ONLY" if args.prepare_only else "LIVE")
    print(f"R5-at-scale [{mode}] — {len(holes)} holes x {len(agents)} agents "
          f"({', '.join(a['name'] for a in agents)})", file=sys.stderr)

    results = []
    for h in holes:
        r = run_hole(h, agents, out_root, llmll, timeout, args.mock, args.prepare_only)
        results.append(r)
        if not args.prepare_only:
            sp = r.get("status_partition", {}) or {}
            print(f"  {r['hole']:<20} {r.get('verdict','-'):<26} "
                  f"verified={len(sp.get('verified',[]))} "
                  f"type_error={len(sp.get('type_error',[]))} "
                  f"refuted={len(sp.get('refuted',[]))}", file=sys.stderr)

    summary = {"mode": mode, "n_holes": len(holes), "agents": [a["name"] for a in agents],
               "results": results}
    (out_root / "matrix.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
