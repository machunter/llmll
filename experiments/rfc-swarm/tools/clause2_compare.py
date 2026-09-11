#!/usr/bin/env python3
"""CLAUSE-2-COMPARE: decide DRIVER-LL acceptance clause 2 over a live run.

Proposal `docs/design/driver-ll-phase4-proposal.md` Rev 17 section 2.4 splits clause 2
into a THRESHOLDED set, which this tool fails on, and a REPORTED set, which it records
beside the committed oracle without gating.

INDEPENDENCE IS THE WHOLE POINT AND IT IS EASY TO LOSE.
This tool re-derives the reference's declared-output predicates. It does NOT call
`validate.llmll`, `registry.llmll` or any part of the LLMLL driver. A comparator that
asks the driver whether the driver was right restates an opinion instead of checking it.
The stage table comes from the REFERENCE (`scripts/rfc_to_implementation.py`'s own
`STAGES` list), and the floors are encoded here with a drift guard (T0) that re-reads
them out of the reference source. If you are tempted to import the port's tables to
save work, that is the failure this paragraph exists to prevent.

THE VERDICT IS A LINE, NOT AN EXIT STATUS. Every cell prints `ok`, `FAIL` or
`NOT CHECKED`, and the run ends on `CLAUSE-2 PASS` or `CLAUSE-2 FAIL: ...`. A caller
greps the line. An exit status alone cannot distinguish "passed" from "did not run",
which is the failure mode this campaign keeps finding.

Usage:
    clause2_compare.py --run RUNDIR --oracle experiments/rfc-swarm/runs/rfc826 \\
                       [--stdout CAPTURE] [--reference scripts/rfc_to_implementation.py]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
REFERENCE = REPO / "scripts" / "rfc_to_implementation.py"
DRIVER_SRC = REPO / "tools" / "llmll-driver"
RFC_COVERAGE = REPO / "scripts" / "rfc_coverage.py"

# The reference's per-stage byte floors, keyed by stage key.
#   B  200  rfc_to_implementation.py, stage_B, `out.stat().st_size > 200`
#   C  400  stage_C, `out.stat().st_size > 400`
# Every other stage declares no floor. A negative floor does NOT disable the
# presence check: that one is per delegated call, and it holds for every floor.
# T0 re-reads these from the reference source so this table cannot drift silently.
FLOORS = {"B": 200, "C": 400}

TERMINAL = {"complete", "stopped", "failed"}


class Report:
    """Collects cell verdicts and prints them. Failures are thresholded; notes are not."""

    def __init__(self) -> None:
        self.failures: list[str] = []
        self.unchecked: list[str] = []
        self.lines: list[str] = []

    def ok(self, cell: str, msg: str) -> None:
        self.lines.append(f"  ok           {cell:<3} {msg}")

    def fail(self, cell: str, msg: str) -> None:
        self.failures.append(cell)
        self.lines.append(f"  FAIL         {cell:<3} {msg}")

    def unchecked_cell(self, cell: str, msg: str) -> None:
        self.unchecked.append(cell)
        self.lines.append(f"  NOT CHECKED  {cell:<3} {msg}")

    def note(self, label: str, msg: str) -> None:
        self.lines.append(f"  {label:<20} {msg}")


def load_reference(path: pathlib.Path):
    """Import the Python driver for its STAGES table. The reference is the oracle."""
    spec = importlib.util.spec_from_file_location("rfc_reference", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"CLAUSE-2 FAIL: cannot import the reference at {path}")
    mod = importlib.util.module_from_spec(spec)
    # Register BEFORE exec_module. A dataclass in the reference resolves its field
    # types through sys.modules[cls.__module__], which is None for an unregistered
    # module, and the import dies with a bare AttributeError on Python 3.9.
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


UNREADABLE = object()


def read_json(path: pathlib.Path, *, fatal: bool = True):
    """Read a JSON artifact.

    `fatal` is the THRESHOLDED half's setting: a malformed MANIFEST.json is a run
    that recorded nothing and must stop the tool. The REPORTED half passes
    fatal=False, because a reported class never gates: a malformed artifact there
    is recorded as unreadable and the run still reaches its verdict. A reported
    class that can kill the run is a thresholded class wearing the wrong label.
    """
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except json.JSONDecodeError as e:
        if fatal:
            raise SystemExit(f"CLAUSE-2 FAIL: {path} is not readable JSON ({e})")
        return UNREADABLE


# --------------------------------------------------------------------------
# T0: the drift guard on this file's own floor table.
# --------------------------------------------------------------------------
def t0_floor_drift(rep: Report, reference_src: str) -> None:
    found = sorted(int(n) for n in re.findall(r"st_size\s*>\s*(\d+)", reference_src))
    want = sorted(FLOORS.values())
    if found == want:
        rep.ok("T0", f"floor table matches the reference: {want}")
    else:
        rep.fail("T0", f"floor drift: this tool encodes {want}, the reference has {found}. "
                       "Re-read the reference and update FLOORS before trusting T4.")


# --------------------------------------------------------------------------
# T1: a terminal state over every stage the registry enumerates.
# --------------------------------------------------------------------------
def t1_terminal(rep: Report, stages, manifest: dict) -> None:
    rows = manifest.get("stages") or {}
    if not rows:
        rep.fail("T1", "MANIFEST.json records no stages at all. An empty population is "
                       "not agreement; it is a run that did not happen.")
        return
    missing = [st.key for st in stages if st.key not in rows]
    nonterminal = [st.key for st in stages
                   if st.key in rows and rows[st.key].get("status") not in TERMINAL]
    if missing or nonterminal:
        parts = []
        if missing:
            parts.append(f"no row for {', '.join(missing)}")
        if nonterminal:
            parts.append(f"non-terminal status at {', '.join(nonterminal)}")
        rep.fail("T1", f"{len(stages)} stages enumerated; " + "; ".join(parts))
    else:
        rep.ok("T1", f"terminal state over all {len(stages)} enumerated stages "
                     "(the specification's fifteen plus G2, the artifact audit)")


# --------------------------------------------------------------------------
# T2: zero FFI declarations. Authority has no definition and is NOT checked.
# --------------------------------------------------------------------------
def t2_ffi(rep: Report) -> None:
    if not DRIVER_SRC.is_dir():
        rep.fail("T2", f"{DRIVER_SRC} is absent; the FFI count has no population")
        return
    hits: list[str] = []
    for f in sorted(DRIVER_SRC.glob("*.llmll")):
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"\((?:haskell|c)\.[A-Za-z0-9_.-]+", line):
                hits.append(f"{f.name}:{i}")
    if hits:
        rep.fail("T2", f"{len(hits)} FFI declaration(s), and the campaign bar is zero: "
                       + ", ".join(hits[:5]))
    else:
        rep.ok("T2", f"0 FFI declarations across {len(list(DRIVER_SRC.glob('*.llmll')))} "
                     "driver modules (bar is 0)")
    rep.unchecked_cell("T2b", "bounded authority: the clause carries it forward and no "
                              "artifact defines a check for it. Reported as unchecked "
                              "rather than asserted.")


# --------------------------------------------------------------------------
# T3: every halting stage names its reason on its output.
# --------------------------------------------------------------------------
def t3_halt_on_output(rep: Report, manifest: dict, capture: pathlib.Path | None) -> None:
    rows = manifest.get("stages") or {}
    halts = {k: v for k, v in rows.items() if v.get("status") in {"stopped", "failed"}}
    if capture is None:
        rep.unchecked_cell("T3", f"{len(halts)} halt(s) recorded, and no --stdout capture "
                                 "was given. driver-spec section 4:139-143 is about the "
                                 "operator's output, which the manifest cannot witness.")
        return
    text = capture.read_text(encoding="utf-8", errors="replace")
    silent = [k for k, v in halts.items() if str(v.get("detail", "")) not in text]
    if not halts:
        rep.ok("T3", "no halting stage in this run; the clause is vacuous here and says so")
    elif silent:
        rep.fail("T3", f"{len(silent)} halt(s) recorded but not reported on the output: "
                       + ", ".join(silent))
    else:
        rep.ok("T3", f"all {len(halts)} halt(s) name their reason on the output")


# --------------------------------------------------------------------------
# T4: no `complete` over an artifact the reference's predicates reject.
# --------------------------------------------------------------------------
def t4_complete_shape(rep: Report, stages, manifest: dict, run: pathlib.Path) -> None:
    rows = manifest.get("stages") or {}
    bad: list[str] = []
    checked = 0
    for st in stages:
        rec = rows.get(st.key)
        if not rec or rec.get("status") != "complete":
            continue
        for out in st.outputs:
            p = run / out
            checked += 1
            if not p.exists():
                bad.append(f"{st.key}: {out} absent (presence)")
                continue
            floor = FLOORS.get(st.key)
            if floor is not None and p.stat().st_size <= floor:
                bad.append(f"{st.key}: {out} is {p.stat().st_size} bytes, floor {floor}")
    if bad:
        rep.fail("T4", f"{len(bad)} declared artifact(s) rejected by the reference's own "
                       "predicates while the stage recorded complete: " + "; ".join(bad[:4]))
    elif checked == 0:
        rep.fail("T4", "no complete stage declared any output. A check with an empty "
                       "population passes by not running, which is not a pass.")
    else:
        rep.ok("T4", f"{checked} declared artifact(s) meet presence and floor")


# --------------------------------------------------------------------------
# T5: BLOCKED. See the module docstring and the plan's finding.
# --------------------------------------------------------------------------
def t5_stopped_for_failed(rep: Report) -> None:
    rep.unchecked_cell(
        "T5", "stopped-for-failed: the clause compares against the reference's recorded "
              "status, which lives in MANIFEST.json, and NO committed run carries one. "
              "Blocked on a proposal revision; see the plan's finding. Not substituted "
              "with a different reading here.")


# --------------------------------------------------------------------------
# Reported classes. Recorded with n, never thresholded.
# --------------------------------------------------------------------------
def reported(rep: Report, stages, manifest: dict, run: pathlib.Path,
             oracle: pathlib.Path) -> None:
    rows = manifest.get("stages") or {}
    counts: dict[str, int] = {}
    for st in stages:
        s = (rows.get(st.key) or {}).get("status", "absent")
        counts[s] = counts.get(s, 0) + 1
    rep.note("R1 stage status", f"run {counts} / oracle NO ORACLE "
                                "(clause 1a owns this class, Rev 16 section 2.4)")

    run_gate = read_json(run / "09-gate" / "gate.json", fatal=False)
    or_gate = read_json(oracle / "gate.json", fatal=False)
    rep.note("R2 gate J", _gate_line(run_gate, or_gate))

    run_rec = read_json(run / "04-reconcile" / "reconciliation-summary.json", fatal=False)
    or_rec = read_json(oracle / "reconciliation-summary.json", fatal=False)
    rep.note("R3 stage E", _rec_line(run_rec, or_rec))

    rep.note("R4 stage L", _cov_line(run, oracle))

    run_wave = read_json(run / "wave.json", fatal=False)
    or_wave = read_json(oracle / "wave.json", fatal=False)
    rep.note("R5 wave partition", _wave_line(run_wave, or_wave))
    rep.note("R6 retry budget", _attempts_line(run_wave, or_wave))


def _gate_line(run_g, or_g) -> str:
    def sketch(g):
        if g is UNREADABLE:
            return "unreadable JSON"
        if not g:
            return "absent"
        cc = (g.get("characteristic_core") or {}).get("dispositioned_out", None)
        ex = g.get("exclusions_outside_barrier_list", None)
        vs = g.get("verifiable_subject_matter") or {}
        verdict = "PASS" if cc == [] and ex == [] else "HALT"
        return (f"{verdict} core_out={len(cc) if cc is not None else '?'} "
                f"outside_barrier={len(ex) if ex is not None else '?'} "
                f"carried={vs.get('carried', '?')}/{vs.get('total', '?')}")
    return f"run {sketch(run_g)} / oracle {sketch(or_g)}"


def _rec_line(run_r, or_r) -> str:
    def sketch(r):
        if r is UNREADABLE:
            return "unreadable JSON"
        if not r:
            return "absent"
        lc = r.get("line_coverage") or {}
        first = next(iter(lc.values()), {}) if lc else {}
        ra = r.get("rule_agreement") or {}
        return (f"a_only={r.get('a_only', '?')} b_only={r.get('b_only', '?')} "
                f"jaccard={first.get('jaccard', '?')} kappa={ra.get('cohens_kappa', '?')} "
                f"n_compared={ra.get('compared', '?')}")
    return f"run {sketch(run_r)} / oracle {sketch(or_r)}"


def _cov_line(run: pathlib.Path, oracle: pathlib.Path) -> str:
    """Stage L's verdict. The oracle records it in RESULTS.md prose, so name how to re-derive it."""
    run_inv = next(iter(sorted(run.glob("*/inventory-dispositioned.json"))), None)
    run_side = f"inventory at {run_inv.relative_to(run)}" if run_inv else "no inventory found"
    inv = oracle / "inventory-dispositioned.json"
    if not (RFC_COVERAGE.exists() and inv.exists()):
        return f"run {run_side} / oracle NOT RE-DERIVABLE (rfc_coverage.py or the inventory is absent)"
    return (f"run {run_side} / oracle re-derivable via "
            f"`python3 {RFC_COVERAGE.name} --inventory {inv.name} --trust-report ... --json`; "
            "RESULTS.md records PASS 39/39 Encoded, 19/19 core as prose only")


def _wave_line(run_w, or_w) -> str:
    def sketch(w):
        if w is UNREADABLE:
            return "unreadable JSON"
        if not w:
            return "absent"
        fills = w.get("fills") or []
        by: dict[str, int] = {}
        for f in fills:
            by[f.get("status", "?")] = by.get(f.get("status", "?"), 0) + 1
        return f"n={len(fills)} {by}"
    return f"run {sketch(run_w)} / oracle {sketch(or_w)}"


def _attempts_line(run_w, or_w) -> str:
    def sketch(w):
        if w is UNREADABLE:
            return "unreadable JSON"
        if not w:
            return "absent"
        a = [f.get("attempts") for f in (w.get("fills") or []) if f.get("attempts") is not None]
        return f"n={len(a)} max={max(a) if a else '-'} sum={sum(a) if a else 0}"
    return f"run {sketch(run_w)} / oracle {sketch(or_w)}"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="DRIVER-LL acceptance clause 2 comparator")
    ap.add_argument("--run", required=True, type=pathlib.Path,
                    help="the live run workdir, containing MANIFEST.json")
    ap.add_argument("--oracle", required=True, type=pathlib.Path,
                    help="the committed Python run, e.g. experiments/rfc-swarm/runs/rfc826")
    ap.add_argument("--stdout", type=pathlib.Path, default=None,
                    help="captured console output of the run; T3 is NOT CHECKED without it")
    ap.add_argument("--reference", type=pathlib.Path, default=REFERENCE)
    a = ap.parse_args(argv)

    if not a.run.is_dir():
        print(f"CLAUSE-2 FAIL: --run {a.run} is not a directory")
        return 1
    if not a.oracle.is_dir():
        print(f"CLAUSE-2 FAIL: --oracle {a.oracle} is not a directory")
        return 1

    ref = load_reference(a.reference)
    stages = list(ref.STAGES)
    manifest = read_json(a.run / "MANIFEST.json")
    if manifest is None:
        print(f"CLAUSE-2 FAIL: {a.run / 'MANIFEST.json'} is absent. The run recorded nothing.")
        return 1

    rep = Report()
    print(f"CLAUSE-2 thresholded ({len(stages)} stages enumerated by the reference)")
    t0_floor_drift(rep, a.reference.read_text(encoding="utf-8"))
    t1_terminal(rep, stages, manifest)
    t2_ffi(rep)
    t3_halt_on_output(rep, manifest, a.stdout)
    t4_complete_shape(rep, stages, manifest, a.run)
    t5_stopped_for_failed(rep)
    for line in rep.lines:
        print(line)

    rep2 = Report()
    reported(rep2, stages, manifest, a.run, a.oracle)
    print("CLAUSE-2 reported (not thresholded; divergence here is a finding)")
    for line in rep2.lines:
        print(line)

    if rep.failures:
        print(f"CLAUSE-2 FAIL: {len(rep.failures)} thresholded item(s) unmet "
              f"({', '.join(rep.failures)})")
        return 1
    print(f"CLAUSE-2 PASS: {len(rep.lines) - len(rep.unchecked)} thresholded item(s) met, "
          f"{len(rep.unchecked)} NOT CHECKED ({', '.join(rep.unchecked)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
