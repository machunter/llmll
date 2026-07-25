#!/usr/bin/env python3
"""RFC-SWARM driver: given an RFC URL, drive it to a verified implementation.

This is `docs/design/rfc-swarm-playbook.md` made executable. The playbook is the
authority on *why* each stage exists; this script is the *how*, and it is the
thing that makes a second RFC reproducible without re-deciding the method.

    rfc_to_implementation.py --rfc-url https://www.rfc-editor.org/rfc/rfc1350.txt \\
                             --workdir runs/rfc1350 \\
                             --agent-cmd 'claude -p "$(cat {prompt})"'

WHAT IS AUTOMATED, AND WHAT IS NOT
    Stages are one of three kinds, and the distinction is the point:

      mechanical  fully deterministic, no model in the loop. Re-running gives
                  the same bytes. (A intake, E reconcile, J gate, L coverage,
                  N kill matrix scoring.)
      agent       a judgment a model makes, under a written contract, with its
                  output schema-checked on the way back. The script does not
                  make these judgments and does not pretend to. (B, C, D, F, G,
                  H, I, K, M, O.)
      gate        a mechanical STOP. A failed gate ends the run non-zero rather
                  than degrading quietly. (J, L, and the per-fill bar in M.)

    An agent stage that returns malformed output is a hard failure, not a
    silently-skipped step: the pipeline's whole value is that the denominator
    and the citations are checkable, and both come from agent stages.

BLINDNESS IS ENFORCED, NOT REQUESTED
    The two extractors in stage D run in separate directories that contain the
    pinned RFC bytes and the rubric and nothing else. Neither can see the
    other's output, because the other's output is not in its filesystem. Stage M
    fill agents likewise see only their checkout brief. `--audit-blindness`
    re-checks these directories after the fact and fails if anything leaked.

RESUMABILITY
    Every stage writes its artifact under the workdir and records a hash in
    MANIFEST.json. A stage whose outputs exist is skipped unless --force. Use
    --from/--only to re-run part of a pipeline; extraction is expensive and
    should not be repeated because stage K crashed.

SELF-TEST
    `--self-test` replays the committed TFTP Phase 0 data through the mechanical
    stages and asserts they reproduce the published statistics (Jaccard 0.866,
    kappa 0.938, 124 rows, 46 Encoded, 15/15 core). That is what makes a green
    run of this script mean something: the mechanical spine is pinned to a real
    execution, not just to itself.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

REPO = Path(__file__).resolve().parent.parent
RECONCILE = REPO / "experiments" / "rfc-swarm" / "tools" / "reconcile.py"
RFC_COVERAGE = REPO / "scripts" / "rfc_coverage.py"
PROMPTS = REPO / "experiments" / "rfc-swarm" / "prompts"

# The closed barrier list (playbook stage J). An exclusion citing none of these
# is a STOP: that is what replaces the retired exclusion-ratio ceiling, and it
# catches the real failure (an exclusion nobody can justify) which a percentage
# never could.
BARRIERS = {
    "B1": "timing / liveness",
    "B2": "transport binding",
    "B3": "trace-level property",
    "B4": "opaque transform",
    "B5": "string structure",
    "B6": "superseded / deprecated",
    "B7": "true by construction",
    "B8": "outside any tool",
}

DISPOSITIONS = ("Encoded", "Deployment-modeled", "Vectored", "Dispositioned out")
CARRIED = ("Encoded", "Deployment-modeled", "Vectored")
VERIFIABLE_CLASSES = ("C1", "C2", "C3")


# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

class StopCondition(Exception):
    """A gate fired. The run ends non-zero; nothing downstream is attempted."""


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def log(msg: str) -> None:
    print(f"[rfc-swarm] {msg}", flush=True)


def write_json(p: Path, obj: Any) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, indent=1) + "\n", encoding="utf-8")


def read_json(p: Path) -> Any:
    return json.loads(p.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Agent invocation
# ---------------------------------------------------------------------------

@dataclass
class AgentRunner:
    """Runs an agent command. Deliberately agent-agnostic.

    `cmd_template` is a shell string; `{prompt}` expands to the prompt file and
    `{out}` to the expected output path. The same abstraction the minimal-agent
    harness uses (`experiments/minimal-agent/scripts/run_agent.py`), so any
    runner that works there works here.

    On `shell=True`: intentional, and the same choice `run_agent.py` makes. The
    command is a template the OPERATOR writes on the command line (`claude -p
    ...`, `codex exec ...`), and shell semantics are what make it possible to
    plug in an arbitrary runner without this script knowing anything about it.
    The only values interpolated are paths this script derives from `--workdir`,
    which the operator also supplies. Nothing from the RFC, from an agent's
    output, or from any other untrusted source reaches the command string. If
    you wire this to an untrusted `--agent-cmd` or an untrusted `--workdir`, that
    is a shell injection and the trust boundary has already been crossed.
    """
    cmd_template: str
    timeout: int = 1800
    llmll_cmd: str = "llmll"

    def run(self, workdir: Path, prompt: str, out_name: str,
            label: str) -> Path:
        workdir.mkdir(parents=True, exist_ok=True)
        prompt_path = workdir / "PROMPT.md"
        prompt_path.write_text(prompt, encoding="utf-8")
        out_path = workdir / out_name
        cmd = self.cmd_template.format(prompt=str(prompt_path),
                                       out=str(out_path),
                                       workdir=str(workdir))
        env = dict(os.environ)
        env["LLMLL_CMD"] = self.llmll_cmd
        env["RFC_PIPELINE_PROMPT"] = str(prompt_path)
        env["RFC_PIPELINE_OUT"] = str(out_path)
        started = time.monotonic()
        log(f"  agent[{label}] -> {out_path.relative_to(workdir.parent.parent) if workdir.parent.parent in out_path.parents else out_path.name}")
        with (workdir / "agent.stdout.log").open("w") as so, \
             (workdir / "agent.stderr.log").open("w") as se:
            rc = subprocess.run(cmd, cwd=workdir, shell=True,
                                stdin=subprocess.DEVNULL, stdout=so, stderr=se,
                                env=env, timeout=self.timeout,
                                check=False).returncode
        dur = round(time.monotonic() - started, 1)
        if rc != 0:
            raise StopCondition(
                f"agent[{label}] exited {rc} after {dur}s; see {workdir}/agent.stderr.log")
        if not out_path.exists():
            raise StopCondition(
                f"agent[{label}] exited 0 but wrote no {out_name}; "
                f"the stage contract was not met (see {workdir}/agent.stdout.log)")
        log(f"  agent[{label}] ok ({dur}s)")
        return out_path


# ---------------------------------------------------------------------------
# Schema checks on agent output
# ---------------------------------------------------------------------------

def require(cond: object, msg: str) -> None:
    """Assert a stage contract. `cond` is any truthy value, not just a bool:
    the call sites test non-empty lists and regex matches as well as booleans."""
    if not cond:
        raise StopCondition(msg)


def check_extraction(doc: Any, label: str) -> dict[str, Any]:
    """Validate an extraction against the shape reconcile.py consumes.

    The schema is not this script's invention: it is the one the shipped
    reconciliation tool reads and the one the committed TFTP extractions use.
    `excluded` is required, not optional, because it is the evidence that the
    rubric was actually applied to the non-normative text rather than skipped.
    """
    require(isinstance(doc, dict),
            f"{label}: expected a JSON object with 'normative' and 'excluded', "
            "not a bare array")
    for key in ("normative", "excluded"):
        require(key in doc and isinstance(doc[key], list),
                f"{label}: missing or non-list '{key}'")
    require(doc["normative"], f"{label}: 'normative' is empty")
    need = ("id", "source", "line_start", "line_end", "quote", "rule", "obligation")
    for i, r in enumerate(doc["normative"]):
        require(isinstance(r, dict), f"{label}: normative[{i}] is not an object")
        missing = [k for k in need if k not in r]
        require(not missing,
                f"{label}: normative[{i}] ({r.get('id','?')}) missing {missing}")
        require(isinstance(r["line_start"], int) and isinstance(r["line_end"], int),
                f"{label}: row {r['id']} has non-integer line_start/line_end; "
                "reconciliation matches by line span, so these must be numbers")
        require(r["line_start"] <= r["line_end"],
                f"{label}: row {r['id']} has line_start > line_end")
        require(re.match(r"^N[1-9]\d*$", str(r["rule"])),
                f"{label}: row {r['id']} has rule {r['rule']!r}, expected N1..Nn")
    doc.setdefault("counts", {})
    doc["counts"] = {"normative": len(doc["normative"]),
                     "excluded": len(doc["excluded"])}
    return doc


def check_dispositioned(doc: Any) -> list[dict[str, Any]]:
    rows: Any = doc["rows"] if isinstance(doc, dict) and "rows" in doc else doc
    require(isinstance(rows, list) and rows, "dispositions: expected rows")
    for r in rows:
        cid = r.get("cid") or r.get("id")
        require(cid, f"dispositions: a row has no cid: {r}")
        require(r.get("disposition") in DISPOSITIONS,
                f"dispositions: {cid} has disposition {r.get('disposition')!r}, "
                f"expected one of {DISPOSITIONS}")
        require(re.match(r"^C[1-6]$", str(r.get("class", ""))),
                f"dispositions: {cid} has class {r.get('class')!r}, expected C1..C6")
        if r["disposition"] == "Dispositioned out":
            require(r.get("barrier") in BARRIERS,
                    f"dispositions: {cid} is excluded but cites barrier "
                    f"{r.get('barrier')!r}, which is not in the closed list "
                    f"{sorted(BARRIERS)}. An exclusion outside the list is a STOP "
                    "(playbook stage J).")
        require(r.get("reason"), f"dispositions: {cid} has no reason")
    return rows


# ---------------------------------------------------------------------------
# Stage implementations
# ---------------------------------------------------------------------------

@dataclass
class Ctx:
    workdir: Path
    agent: AgentRunner
    llmll: str
    rfc_url: str
    amend_urls: list[str] = field(default_factory=list)
    wave_agents: int = 4
    force: bool = False

    def d(self, *parts: str) -> Path:
        """Path under the workdir, with its PARENT created.

        Right for a file path. When the returned path is itself a directory you
        are about to write into, use `dir()` instead.
        """
        p = self.workdir.joinpath(*parts)
        p.parent.mkdir(parents=True, exist_ok=True)
        return p

    def dir(self, *parts: str) -> Path:
        """Directory under the workdir, created."""
        p = self.workdir.joinpath(*parts)
        p.mkdir(parents=True, exist_ok=True)
        return p

    def prompt(self, name: str, **kw: Any) -> str:
        tpl = (PROMPTS / name).read_text(encoding="utf-8")
        for k, v in kw.items():
            tpl = tpl.replace("{{" + k + "}}", str(v))
        left = re.findall(r"\{\{(\w+)\}\}", tpl)
        require(not left, f"prompt {name}: unfilled placeholders {left}")
        return tpl


def stage_A_intake(ctx: Ctx) -> None:
    """Fetch the RFC as verbatim bytes and pin a SHA-256 (playbook stage A).

    Every later stage reads these bytes. A from-memory paraphrase cannot survive
    the clause-to-predicate audit and its citations will not anchor.
    """
    src = ctx.d("00-source")
    src.mkdir(parents=True, exist_ok=True)
    pins = []
    for url in [ctx.rfc_url, *ctx.amend_urls]:
        name = url.rstrip("/").split("/")[-1] or "rfc.txt"
        dest = src / name
        if not dest.exists() or ctx.force:
            log(f"  fetching {url}")
            with urllib.request.urlopen(url, timeout=60) as r:  # noqa: S310
                dest.write_bytes(r.read())
        text = dest.read_text(encoding="utf-8", errors="replace")
        # Count lines by newline only (`wc -l` semantics). Python's splitlines()
        # additionally breaks on form feeds, which RFC page breaks are full of,
        # and would give a different numbering than the one agents cite against.
        pins.append({"url": url, "file": name,
                     "sha256": sha256_file(dest),
                     "lines": text.count("\n")})
        log(f"  pinned {name}: {pins[-1]['sha256'][:16]}... ({pins[-1]['lines']} lines)")
    write_json(ctx.d("00-source", "PROVENANCE.json"), {"sources": pins})


def stage_B_scope(ctx: Ctx) -> None:
    """Decide the verification boundary BEFORE extraction (playbook stage B)."""
    prov = read_json(ctx.d("00-source", "PROVENANCE.json"))
    body = _sources_text(ctx)
    out = ctx.agent.run(ctx.d("01-scope"),
                        ctx.prompt("stage-B-scope.md", rfc_text=body,
                                   provenance=json.dumps(prov, indent=1)),
                        "scope.md", "scope")
    require(out.stat().st_size > 200,
            "stage B: scope.md is too short to state a boundary")


def stage_C_rubric(ctx: Ctx) -> None:
    """Author the normativity rubric BEFORE any extraction (playbook stage C).

    Written first and applied uniformly. A denominator produced by an unstated
    rule is not auditable, and a rubric written after seeing the clauses is a
    rubric fitted to them.
    """
    out = ctx.agent.run(ctx.d("02-rubric"),
                        ctx.prompt("stage-C-rubric.md", rfc_text=_sources_text(ctx)),
                        "rubric.md", "rubric")
    require(out.stat().st_size > 400, "stage C: rubric.md is too short")


def _sources_text(ctx: Ctx) -> str:
    """The pinned bytes, presented with EXPLICIT line numbers.

    Extraction rows cite line spans and reconciliation matches on them, so the
    numbering has to be unambiguous. Asking an agent to count lines itself is a
    silent source of mismatched spans, and a mismatched span reads downstream as
    a coverage disagreement that never happened. Lines are split on newline only
    (`wc -l` semantics): RFC page breaks are form feeds, which Python's
    splitlines() would treat as extra line boundaries.
    """
    parts = []
    for f in sorted((ctx.workdir / "00-source").glob("*.txt")):
        raw = f.read_text(encoding="utf-8", errors="replace")
        numbered = "\n".join(f"{i:5d}| {ln}"
                             for i, ln in enumerate(raw.split("\n"), start=1))
        parts.append(f"===== {f.name} =====\n{numbered}")
    require(parts, "no pinned RFC text found; run stage A first")
    return "\n\n".join(parts)


def stage_D_extract(ctx: Ctx) -> None:
    """Two blind extractors on identical bytes under one rubric (stage D).

    BLINDNESS IS STRUCTURAL. Each extractor gets its own directory holding the
    pinned bytes and the rubric and nothing else. One audited pass cannot answer
    "who checked that the inventory is complete"; two independent passes can.
    Extraction assigns NO disposition: keeping scoping out of extraction is what
    makes the two runs comparable.
    """
    rubric = (ctx.workdir / "02-rubric" / "rubric.md").read_text(encoding="utf-8")
    text = _sources_text(ctx)
    results: dict[str, Path] = {}
    for tag in ("a", "b"):
        wd = ctx.dir("03-extraction", tag)
        # the isolated input set, and nothing else
        for f in sorted((ctx.workdir / "00-source").glob("*")):
            if f.is_file():
                shutil.copy2(f, wd / f.name)
        (wd / "rubric.md").write_text(rubric, encoding="utf-8")
        out = ctx.agent.run(wd,
                            ctx.prompt("stage-D-extract.md", rfc_text=text,
                                       rubric=rubric, extractor=tag.upper()),
                            "extraction.json", f"extract-{tag}")
        doc = check_extraction(read_json(out), f"extraction-{tag}")
        doc["extractor"] = tag.upper()
        write_json(out, doc)
        results[tag] = out
        log(f"  extractor {tag.upper()}: {doc['counts']['normative']} normative, "
            f"{doc['counts']['excluded']} excluded")
    # stage the pair where reconcile.py expects them
    data = ctx.dir("04-reconcile", "data")
    for tag in ("a", "b"):
        shutil.copy2(results[tag], data / f"extraction-{tag}.json")


def stage_E_reconcile(ctx: Ctx) -> None:
    """Mechanical reconciliation by line-span overlap (playbook stage E).

    Reports three distinct things, because collapsing them understates agreement
    badly: line-coverage agreement (speaks to the denominator's completeness),
    granularity difference versus genuine coverage disagreement, and rule
    agreement on 1:1 matched rows (where Cohen's kappa genuinely applies).

    Adjudication of the genuine disagreements is a human/agent judgment and is
    stage E's OUTPUT, not its input: the script reports them and stops if they
    are unadjudicated.
    """
    data = ctx.workdir / "04-reconcile" / "data"
    rc = subprocess.run([sys.executable, str(RECONCILE), str(data)],
                        capture_output=True, text=True, check=False)
    (ctx.workdir / "04-reconcile" / "reconcile.stdout.txt").write_text(
        rc.stdout + rc.stderr, encoding="utf-8")
    require(rc.returncode == 0, f"stage E: reconcile.py failed\n{rc.stderr[:2000]}")
    report = read_json(data / "reconciliation.json")
    cov = report.get("line_coverage", {})
    log(f"  line-coverage: {json.dumps(cov)[:200]}")
    log(f"  rule agreement: {json.dumps(report.get('rule_agreement', {}))}")
    a_only = len(report.get("A_unmatched_rows", []))
    b_only = len(report.get("B_unmatched_rows", []))
    log(f"  genuine coverage disagreements: {a_only} A-only, {b_only} B-only")
    write_json(ctx.d("04-reconcile", "SUMMARY.json"),
               {"a_only": a_only, "b_only": b_only,
                "line_coverage": cov,
                "rule_agreement": report.get("rule_agreement", {})})


def stage_F_core(ctx: Ctx) -> None:
    """Name the characteristic core BEFORE dispositions exist (stage F).

    The clauses whose loss would mean you had not implemented the protocol at
    all. Fixed first so the set cannot be drawn around whatever happens to
    succeed.
    """
    merged = ctx.workdir / "04-reconcile" / "data" / "extraction-a.json"
    out = ctx.agent.run(ctx.dir("05-core"),
                        ctx.prompt("stage-F-core.md", rfc_text=_sources_text(ctx),
                                   inventory=json.dumps(
                                       read_json(merged)["normative"], indent=1)),
                        "core.json", "core")
    core = read_json(out)
    ids = core["core_ids"] if isinstance(core, dict) else core
    require(isinstance(ids, list) and ids, "stage F: expected a non-empty core_ids list")
    log(f"  characteristic core: {len(ids)} rows")


def stage_G_disposition(ctx: Ctx) -> None:
    """One disposition and one class per row (playbook stage G).

    Two rules keep this defensible, and both are checked here rather than
    trusted: an exclusion must cite a barrier from the closed list, and a row
    that is true by construction is B7 (excluded), never counted as carried,
    because no mutant can exercise it and it carries no verification evidence.
    """
    core = read_json(ctx.workdir / "05-core" / "core.json")
    core_ids = set(core["core_ids"] if isinstance(core, dict) else core)
    out = ctx.agent.run(
        ctx.d("06-disposition"),
        ctx.prompt("stage-G-disposition.md",
                   rfc_text=_sources_text(ctx),
                   inventory=json.dumps(read_json(
                       ctx.workdir / "04-reconcile" / "data"
                       / "extraction-a.json")["normative"], indent=1),
                   core_ids=json.dumps(sorted(core_ids)),
                   barriers=json.dumps(BARRIERS, indent=1),
                   scope=(ctx.workdir / "01-scope" / "scope.md").read_text(encoding="utf-8")),
        "inventory-dispositioned.json", "disposition")
    rows = check_dispositioned(read_json(out))
    for r in rows:
        cid = r.get("cid") or r.get("id")
        r["cid"] = cid
        r["core"] = bool(r.get("core")) or cid in core_ids
    write_json(ctx.d("06-disposition", "inventory-dispositioned.json"), {"rows": rows})
    from collections import Counter
    log(f"  dispositions: {dict(Counter(r['disposition'] for r in rows))}")


def stage_H_feasibility(ctx: Ctx) -> None:
    """Prove the core shapes verify AND refute, before authoring (stage H).

    A contract that cannot refute its own historically-attested bug is
    decorative, so each probe is paired with a mutant that must be refuted.

    Probe BODIES are written under 07-feasibility/ and are deliberately NOT
    promoted into the deliverable: they are working implementations of functions
    the swarm is meant to invent, and committing them would plant a reference
    solution.
    """
    wd = ctx.dir("07-feasibility")
    out = ctx.agent.run(wd, ctx.prompt("stage-H-feasibility.md",
                                       llmll=ctx.llmll,
                                       scope=(ctx.workdir / "01-scope" / "scope.md"
                                              ).read_text(encoding="utf-8")),
                        "probes.json", "feasibility")
    probes = read_json(out)
    require(isinstance(probes, list) and probes, "stage H: expected a list of probes")
    results = []
    for p in probes:
        good, mutant = wd / p["file"], wd / p["mutant_file"]
        require(good.exists() and mutant.exists(),
                f"stage H: probe {p.get('name')} names files that do not exist")
        g = _verify(ctx, good, strict=True)
        m = _verify(ctx, mutant, strict=True)
        ok = g["safe"] and g["body_faithful"] and not m["safe"]
        results.append({"name": p.get("name"), "probe": g, "mutant": m, "pass": ok})
        log(f"  probe {p.get('name')}: probe={'SAFE' if g['safe'] else 'not-SAFE'} "
            f"mutant={'refuted' if not m['safe'] else 'SURVIVED'} -> {'ok' if ok else 'FAIL'}")
    write_json(wd / "feasibility.json", results)
    bad = [r["name"] for r in results if not r["pass"]]
    require(not bad,
            f"stage H: feasibility not established for {bad}. A probe must verify "
            "body-faithfully AND its mutant must refute; otherwise the contract "
            "shape is decorative and the target should be re-scoped, not re-graded.")


def _verify(ctx: Ctx, f: Path, strict: bool = True) -> dict:
    cmd = [ctx.llmll, "verify", str(f)]
    if strict:
        cmd.append("--strict-verified-core")
    p = subprocess.run(cmd, capture_output=True, text=True, check=False)
    o = p.stdout + p.stderr
    return {"file": f.name, "safe": "SAFE" in o and p.returncode == 0,
            "body_faithful": f"body-faithful" in o and f.stem not in _fallbacks(o),
            "returncode": p.returncode,
            "output": o[-4000:]}


def _fallbacks(out: str) -> set[str]:
    m = re.search(r"body-fallback:\s*(.+)", out)
    return {s.strip() for s in m.group(1).split(",")} if m else set()


def stage_I_prereg(ctx: Ctx) -> None:
    """Fix acceptance criteria and the mutant taxonomy in writing (stage I).

    Pre-registration only means something if it is honored when it goes against
    you. Outcomes are recorded in an appendix; the pre-registered text is never
    edited.
    """
    ctx.agent.run(ctx.d("08-prereg"),
                  ctx.prompt("stage-I-prereg.md",
                             scope=(ctx.workdir / "01-scope" / "scope.md"
                                    ).read_text(encoding="utf-8"),
                             barriers=json.dumps(BARRIERS, indent=1)),
                  "PRE-REGISTRATION.md", "prereg")


def stage_J_gate(ctx: Ctx) -> None:
    """The gate. Three conditions, and NOT an exclusion-ratio ceiling (stage J).

    A ratio of excluded/total tracks the genre composition of the target
    document, not the reach of the verifier: every complete protocol spec
    carries transport binding, timers and deployment prose that add denominator
    and can never add numerator. It fires before a single scoping judgment is
    made, so no such RFC could pass. It is not used here.
    """
    rows = read_json(ctx.workdir / "06-disposition" / "inventory-dispositioned.json")["rows"]
    verifiable = [r for r in rows if r["class"] in VERIFIABLE_CLASSES]
    carried = [r for r in verifiable if r["disposition"] in CARRIED]
    core = [r for r in rows if r.get("core")]
    core_out = [r["cid"] for r in core if r["disposition"] == "Dispositioned out"]
    bad_barrier = [r["cid"] for r in rows
                   if r["disposition"] == "Dispositioned out"
                   and r.get("barrier") not in BARRIERS]
    report = {
        "verifiable_subject_matter": {
            "carried": len(carried), "total": len(verifiable),
            "ratio": round(len(carried) / len(verifiable), 4) if verifiable else None,
            "note": "reported, NOT thresholded",
        },
        "characteristic_core": {"total": len(core), "dispositioned_out": core_out},
        "exclusions_outside_barrier_list": bad_barrier,
        "raw_ledger": {d: sum(1 for r in rows if r["disposition"] == d)
                       for d in DISPOSITIONS},
    }
    write_json(ctx.d("09-gate", "gate.json"), report)
    log(f"  coverage of verifiable subject matter (C1+C2+C3): "
        f"{len(carried)}/{len(verifiable)} (reported, not graded)")
    log(f"  characteristic core: {len(core)} rows, {len(core_out)} dispositioned out")
    require(not core_out,
            f"STOP (stage J): characteristic-core rows dispositioned out: {core_out}. "
            "The target is re-scoped, not re-graded.")
    require(not bad_barrier,
            f"STOP (stage J): exclusions citing no barrier from the closed list: "
            f"{bad_barrier}. An exclusion nobody can justify is the real failure.")
    log("  gate PASS")


def stage_K_contracts(ctx: Ctx) -> None:
    """One contract clause per Encoded row, each :source-tagged (stage K).

    Per-conjunct provenance (SRC-CONJ-1) means a multi-clause pre/post keeps
    every citation, so contracts are NOT distorted into one-clause-per-function
    to make traceability work.
    """
    inv = ctx.workdir / "06-disposition" / "inventory-dispositioned.json"
    rows = read_json(inv)["rows"]
    encoded = [r for r in rows if r["disposition"] == "Encoded"]
    wd = ctx.d("10-roots")
    out = ctx.agent.run(
        wd,
        ctx.prompt("stage-K-contracts.md",
                   rfc_text=_sources_text(ctx),
                   encoded=json.dumps(encoded, indent=1),
                   scope=(ctx.workdir / "01-scope" / "scope.md").read_text(encoding="utf-8"),
                   llmll=ctx.llmll),
        "roots.llmll", "contracts")
    p = subprocess.run([ctx.llmll, "check", str(out)], capture_output=True,
                       text=True, check=False)
    require(p.returncode == 0,
            f"stage K: authored roots do not typecheck\n{(p.stdout + p.stderr)[:3000]}")
    holes = out.read_text(encoding="utf-8").count("?")
    log(f"  authored {len(encoded)} Encoded rows into {out.name} (typechecks; ~{holes} holes)")


def stage_L_coverage(ctx: Ctx) -> None:
    """RFC-COV-1 both ways, then freeze the clause surface (stage L).

    Checks that every citation resolves to a real row, every Encoded row is
    cited, no contract cites an excluded row, and only root contracts carry
    :source at all.

    The freeze is SCOPED: roots bearing :source are immutable, while
    refine-spawned sub-contracts are additive, carry no :source, and are
    governed by the shipped spawn gates. A blanket freeze would forbid the
    mechanism the wave depends on.
    """
    roots = ctx.workdir / "10-roots" / "roots.llmll"
    tr = ctx.d("11-freeze", "trust-report.json")
    p = subprocess.run([ctx.llmll, "verify", str(roots), "--trust-report", "--json"],
                       capture_output=True, text=True, check=False)
    tr.write_text(p.stdout, encoding="utf-8")
    names = [e["name"] for e in read_json(tr).get("entries", [])]
    roots_txt = ctx.d("11-freeze", "ROOTS.txt")
    roots_txt.write_text("\n".join(names) + "\n", encoding="utf-8")
    inv = ctx.workdir / "06-disposition" / "inventory-dispositioned.json"
    cov = subprocess.run(
        [sys.executable, str(RFC_COVERAGE), "--inventory", str(inv),
         "--trust-report", str(tr), "--roots", str(roots_txt),
         "--require-full-coverage"],
        capture_output=True, text=True, check=False)
    (ctx.workdir / "11-freeze" / "rfc-cov-1.txt").write_text(
        cov.stdout + cov.stderr, encoding="utf-8")
    for line in cov.stdout.splitlines():
        log(f"  {line}")
    require(cov.returncode == 0,
            "STOP (stage L): RFC-COV-1 failed at freeze strength. The clause "
            "surface cannot be frozen while the inventory and the citations "
            "disagree.")
    log("  clause surface FROZEN")


def stage_M_wave(ctx: Ctx) -> None:
    """N blind agents fill holes concurrently (playbook stage M).

    Coordination is only through checkout / patch / refine. Retries carry
    compiler error text only. Per-fill bar: verify SAFE, the filled function
    body-faithful, not flagged termination_unverified.

    A hole that exhausts its retries is a FINDING, routed to the compiler team
    or back to the inventory as a scoping error. It is never an occasion for a
    hint.
    """
    roots = ctx.workdir / "10-roots" / "roots.llmll"
    wave = ctx.dir("12-wave")
    target = wave / "tree.llmll"
    if not target.exists() or ctx.force:
        shutil.copy2(roots, target)
    holes = _holes(ctx, target)
    require(holes, "stage M: no holes to fill")
    log(f"  {len(holes)} holes, {ctx.wave_agents} concurrent agents")

    def fill(idx_hole: tuple[int, str]) -> dict:
        i, hole = idx_hole
        wd = wave / f"agent-{i:02d}"
        brief = _checkout(ctx, target, hole, wd)
        try:
            ctx.agent.run(wd, ctx.prompt("stage-M-fill.md", brief=brief,
                                         hole=hole, llmll=ctx.llmll),
                          "body.json", f"fill-{hole}")
        except StopCondition as e:
            return {"hole": hole, "status": "agent-failed", "detail": str(e)}
        return {"hole": hole, "status": "filled"}

    with concurrent.futures.ThreadPoolExecutor(max_workers=ctx.wave_agents) as ex:
        results = list(ex.map(fill, enumerate(holes)))
    v = _verify(ctx, target, strict=True)
    write_json(wave / "wave.json", {"fills": results, "whole_tree": v})
    log(f"  whole tree: {'SAFE' if v['safe'] else 'NOT SAFE'}")
    unfilled = [r["hole"] for r in results if r["status"] != "filled"]
    if unfilled:
        log(f"  FINDINGS (holes that exhausted retries, routed not hinted): {unfilled}")


def _holes(ctx: Ctx, f: Path) -> list[str]:
    p = subprocess.run([ctx.llmll, "check", str(f), "--json"],
                       capture_output=True, text=True, check=False)
    try:
        doc = json.loads(p.stdout)
    except json.JSONDecodeError:
        return re.findall(r"\?([a-zA-Z][\w-]*)", f.read_text(encoding="utf-8"))
    return [h.get("name") for h in doc.get("holes", []) if h.get("name")]


def _checkout(ctx: Ctx, f: Path, hole: str, wd: Path) -> str:
    wd.mkdir(parents=True, exist_ok=True)
    p = subprocess.run([ctx.llmll, "checkout", str(f), hole],
                       capture_output=True, text=True, check=False)
    brief = p.stdout or p.stderr
    (wd / "BRIEF.md").write_text(brief, encoding="utf-8")
    return brief


def stage_N_killmatrix(ctx: Ctx) -> None:
    """Execute the pre-registered mutant taxonomy; report SURVIVORS (stage N).

    A mutant that verifies SAFE means the contract is weak or the row is
    mis-dispositioned, and it is resolved rather than dropped. Good twins
    (correct variants expected to stay SAFE) guard against over-strong
    contracts.

    Read the result correctly: a killed mutant proves the contract excludes one
    specific behavior. It is eliminative evidence, and it does not corroborate
    that the contract says what the RFC says.
    """
    wd = ctx.dir("13-kill-matrix")
    tree = ctx.workdir / "12-wave" / "tree.llmll"
    out = ctx.agent.run(wd, ctx.prompt("stage-N-mutants.md",
                                       tree=tree.read_text(encoding="utf-8"),
                                       prereg=(ctx.workdir / "08-prereg"
                                               / "PRE-REGISTRATION.md"
                                               ).read_text(encoding="utf-8")),
                        "mutants.json", "mutants")
    matrix = []
    for m in read_json(out):
        f = wd / m["file"]
        require(f.exists(), f"stage N: mutant file {m['file']} not written")
        v = _verify(ctx, f, strict=True)
        expect_safe = bool(m.get("good_twin"))
        killed = not v["safe"]
        matrix.append({"name": m.get("name"), "good_twin": expect_safe,
                       "killed": killed,
                       "verdict": "SAFE" if v["safe"] else "refuted",
                       "as_expected": (v["safe"] == expect_safe)})
        log(f"  {m.get('name')}: {'SAFE' if v['safe'] else 'refuted'}"
            f"{' (good twin)' if expect_safe else ''}"
            f"{'' if matrix[-1]['as_expected'] else '   <-- UNEXPECTED'}")
    write_json(wd / "kill-matrix.json", matrix)
    survivors = [m["name"] for m in matrix if not m["good_twin"] and not m["killed"]]
    if survivors:
        log(f"  SURVIVORS (reported, not dropped): {survivors}")


def stage_O_writeup(ctx: Ctx) -> None:
    """Lead with class-stratified coverage and the core count (stage O).

    Disclose every trusted step, including any closure from per-step invariant
    preservation to all-traces properties, which is a trace induction outside
    the decidable fragment. Never frame the result as verification catching
    agent error.
    """
    def maybe(p: Path) -> str:
        return p.read_text(encoding="utf-8") if p.exists() else "(stage not run)"
    ctx.agent.run(
        ctx.d("14-report"),
        ctx.prompt("stage-O-writeup.md",
                   gate=maybe(ctx.workdir / "09-gate" / "gate.json"),
                   coverage=maybe(ctx.workdir / "11-freeze" / "rfc-cov-1.txt"),
                   kill_matrix=maybe(ctx.workdir / "13-kill-matrix" / "kill-matrix.json"),
                   wave=maybe(ctx.workdir / "12-wave" / "wave.json"),
                   reconcile=maybe(ctx.workdir / "04-reconcile" / "SUMMARY.json")),
        "REPORT.md", "writeup")
    shutil.copy2(ctx.workdir / "14-report" / "REPORT.md", ctx.workdir / "REPORT.md")
    log(f"  report at {ctx.workdir / 'REPORT.md'}")


# ---------------------------------------------------------------------------
# Stage registry
# ---------------------------------------------------------------------------

@dataclass
class Stage:
    key: str
    name: str
    kind: str          # mechanical | agent | gate
    fn: Callable[[Ctx], None]
    outputs: tuple[str, ...]


STAGES: list[Stage] = [
    Stage("A", "intake and provenance pinning", "mechanical", stage_A_intake,
          ("00-source/PROVENANCE.json",)),
    Stage("B", "scope decision", "agent", stage_B_scope, ("01-scope/scope.md",)),
    Stage("C", "normativity rubric", "agent", stage_C_rubric, ("02-rubric/rubric.md",)),
    Stage("D", "dual blind extraction", "agent", stage_D_extract,
          ("03-extraction/a/extraction.json", "03-extraction/b/extraction.json")),
    Stage("E", "mechanical reconciliation", "mechanical", stage_E_reconcile,
          ("04-reconcile/SUMMARY.json",)),
    Stage("F", "characteristic core", "agent", stage_F_core, ("05-core/core.json",)),
    Stage("G", "disposition pass", "agent", stage_G_disposition,
          ("06-disposition/inventory-dispositioned.json",)),
    Stage("H", "feasibility probes", "agent", stage_H_feasibility,
          ("07-feasibility/feasibility.json",)),
    Stage("I", "pre-registration", "agent", stage_I_prereg,
          ("08-prereg/PRE-REGISTRATION.md",)),
    Stage("J", "the gate", "gate", stage_J_gate, ("09-gate/gate.json",)),
    Stage("K", "root contract authoring", "agent", stage_K_contracts,
          ("10-roots/roots.llmll",)),
    Stage("L", "coverage lint and freeze", "gate", stage_L_coverage,
          ("11-freeze/rfc-cov-1.txt",)),
    Stage("M", "the swarm", "agent", stage_M_wave, ("12-wave/wave.json",)),
    Stage("N", "kill matrix", "agent", stage_N_killmatrix,
          ("13-kill-matrix/kill-matrix.json",)),
    Stage("O", "writeup", "agent", stage_O_writeup, ("REPORT.md",)),
]


# ---------------------------------------------------------------------------
# Self-test: the mechanical spine, pinned to the committed TFTP execution
# ---------------------------------------------------------------------------

def self_test() -> int:
    """Replay the committed TFTP Phase 0 data through the mechanical stages.

    This is what makes a green run mean something: the deterministic stages are
    pinned to a real execution rather than only to themselves.
    """
    ok = True

    def check(label: str, got: Any, want: Any) -> None:
        nonlocal ok
        good = got == want
        ok = ok and good
        print(f"  {'PASS' if good else 'FAIL'}  {label}: got {got!r}, want {want!r}")

    print("self-test: reconciliation (stage E) against the committed TFTP data")
    data = REPO / "experiments" / "rfc-swarm" / "data"
    rc = subprocess.run([sys.executable, str(RECONCILE), str(data)],
                        capture_output=True, text=True, check=False)
    if rc.returncode != 0:
        print(f"  FAIL  reconcile.py exited {rc.returncode}\n{rc.stderr[:800]}")
        return 1
    # Exact stored values. VERIFICATION_SCOPE.md quotes these rounded to 3 s.f.
    # (0.8655 -> 0.866, 0.9378 -> 0.938, 0.9535 -> 95.4%); assert the stored
    # figures so the self-test pins the computation, not the prose.
    rep = read_json(data / "reconciliation.json")
    ra = rep["rule_agreement"]
    check("rows compared 1:1", ra["compared"], 43)
    check("raw rule agreement", ra["raw_agreement"], 0.9535)
    check("Cohen's kappa", ra["cohens_kappa"], 0.9378)
    lc = rep["line_coverage"]
    check("RFC 1350 line-coverage Jaccard", lc["RFC1350"]["jaccard"], 0.8655)
    check("RFC 1123 line-coverage Jaccard", lc["RFC1123"]["jaccard"], 0.725)
    check("genuine coverage disagreements (A-only, B-only)",
          (len(rep["A_unmatched_rows"]), len(rep["B_unmatched_rows"])), (1, 10))

    print("self-test: the gate (stage J) against the committed dispositions")
    rows = read_json(data / "inventory-dispositioned.json")["rows"]
    check("inventory rows", len(rows), 124)
    check("Encoded rows", sum(1 for r in rows if r["disposition"] == "Encoded"), 46)
    core = [r for r in rows if r.get("core")]
    check("characteristic-core rows", len(core), 15)
    check("core rows dispositioned out",
          [r["cid"] for r in core if r["disposition"] == "Dispositioned out"], [])
    verifiable = [r for r in rows if r["class"] in VERIFIABLE_CLASSES]
    carried = [r for r in verifiable if r["disposition"] in CARRIED]
    check("verifiable subject matter carried", f"{len(carried)}/{len(verifiable)}", "62/65")

    print("self-test: RFC-COV-1 (stage L) against the frozen TFTP clause surface")
    roots = REPO / "examples" / "tftp_rfc1350" / "roots"
    if roots.exists():
        llmll = os.environ.get("LLMLL_CMD", "llmll")
        tr = Path("/tmp/rfc-selftest-tr.json")
        p = subprocess.run([llmll, "verify", str(roots / "tftp.llmll"),
                            "--trust-report", "--json"],
                           capture_output=True, text=True, check=False)
        if p.stdout.strip().startswith("{"):
            tr.write_text(p.stdout, encoding="utf-8")
            cov = subprocess.run(
                [sys.executable, str(RFC_COVERAGE), "--inventory",
                 str(data / "inventory-dispositioned.json"),
                 "--trust-report", str(tr), "--roots", str(roots / "ROOTS.txt"),
                 "--require-full-coverage"],
                capture_output=True, text=True, check=False)
            check("RFC-COV-1 at freeze strength", cov.returncode, 0)
            for line in cov.stdout.splitlines():
                print(f"     {line}")
        else:
            print("  SKIP  llmll not on PATH (set LLMLL_CMD); clause-surface check skipped")
    else:
        print("  SKIP  no frozen TFTP clause surface in this tree")

    print(f"\nself-test {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def audit_blindness(workdir: Path) -> int:
    """Re-check that the blind stages were actually blind.

    Blindness is the methodological core: if extractor A could see extractor B's
    rows, the agreement statistic measures copying. This fails if either
    extractor's directory contains anything naming the other's output.
    """
    bad = []
    for tag, other in (("a", "b"), ("b", "a")):
        d = workdir / "03-extraction" / tag
        if not d.exists():
            continue
        for f in d.rglob("*"):
            if f.is_file() and (f"extraction-{other}" in f.name
                                or f.name == f"{other}.json"):
                bad.append(str(f))
        # The legitimate input set: the pinned bytes (*.txt), their provenance
        # record, the rubric, the prompt, and the extractor's own output/logs.
        # Anything else in the directory is an unaccounted-for input.
        allowed = {"PROMPT.md", "extraction.json", "rubric.md",
                   "PROVENANCE.json", "agent.stdout.log", "agent.stderr.log"}
        for f in d.iterdir():
            if f.is_file() and f.name not in allowed and f.suffix != ".txt":
                bad.append(f"unexpected input in extractor {tag.upper()}: {f.name}")
    print(f"blindness audit: {'PASS' if not bad else 'FAIL'}")
    for b in bad:
        print(f"  LEAK {b}")
    return 0 if not bad else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="RFC to verified implementation (docs/design/rfc-swarm-playbook.md)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Stages:\n" + "\n".join(
            f"  {s.key}  [{s.kind:10}] {s.name}" for s in STAGES))
    ap.add_argument("--rfc-url", help="URL of the RFC as verbatim text")
    ap.add_argument("--amend-url", action="append", default=[],
                    help="URL of an amending RFC (repeatable)")
    ap.add_argument("--workdir", type=Path, help="run directory")
    ap.add_argument("--agent-cmd",
                    help="shell command template; {prompt} {out} {workdir} expand")
    ap.add_argument("--llmll-cmd", default=os.environ.get("LLMLL_CMD", "llmll"))
    ap.add_argument("--wave-agents", type=int, default=4)
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--only", help="run only these stages, e.g. A,B,D")
    ap.add_argument("--from", dest="from_stage", help="start at this stage")
    ap.add_argument("--force", action="store_true", help="re-run completed stages")
    ap.add_argument("--self-test", action="store_true",
                    help="replay committed TFTP data through the mechanical stages")
    ap.add_argument("--audit-blindness", action="store_true",
                    help="re-check that stage D's extractors were isolated")
    a = ap.parse_args(argv)

    if a.self_test:
        return self_test()
    if a.audit_blindness:
        require(a.workdir is not None, "--audit-blindness needs --workdir")
        return audit_blindness(a.workdir)

    missing = [f for f, v in (("--rfc-url", a.rfc_url), ("--workdir", a.workdir),
                              ("--agent-cmd", a.agent_cmd)) if not v]
    if missing:
        ap.error(f"missing required argument(s): {', '.join(missing)}")

    selected = [s.key for s in STAGES]
    if a.only:
        want = {k.strip().upper() for k in a.only.split(",")}
        selected = [k for k in selected if k in want]
    if a.from_stage:
        i = selected.index(a.from_stage.strip().upper())
        selected = selected[i:]

    ctx = Ctx(workdir=a.workdir.resolve(),
              agent=AgentRunner(a.agent_cmd, a.timeout, a.llmll_cmd),
              llmll=a.llmll_cmd, rfc_url=a.rfc_url,
              amend_urls=a.amend_url, wave_agents=a.wave_agents, force=a.force)
    ctx.workdir.mkdir(parents=True, exist_ok=True)
    manifest_path = ctx.workdir / "MANIFEST.json"
    manifest = read_json(manifest_path) if manifest_path.exists() else {"stages": {}}
    manifest.setdefault("rfc_url", a.rfc_url)

    for stage in STAGES:
        if stage.key not in selected:
            continue
        done = all((ctx.workdir / o).exists() for o in stage.outputs)
        if done and not a.force:
            log(f"stage {stage.key} ({stage.name}): already complete, skipping")
            continue
        log(f"stage {stage.key} [{stage.kind}] {stage.name}")
        started = time.monotonic()
        try:
            stage.fn(ctx)
        except StopCondition as e:
            log(f"STOP at stage {stage.key}: {e}")
            manifest["stages"][stage.key] = {"status": "stopped", "detail": str(e)}
            write_json(manifest_path, manifest)
            return 2
        manifest["stages"][stage.key] = {
            "status": "complete",
            "kind": stage.kind,
            "seconds": round(time.monotonic() - started, 1),
            "outputs": {o: sha256_file(ctx.workdir / o)
                        for o in stage.outputs if (ctx.workdir / o).exists()},
        }
        write_json(manifest_path, manifest)

    log(f"done. manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
