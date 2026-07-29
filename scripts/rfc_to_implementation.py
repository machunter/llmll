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
                  than degrading quietly. (G2, J, L, and the per-fill bar in M.)

    G2 is both: it decides mechanically what a machine can decide about a
    citation and delegates the reading, then evaluates the catalogue itself.

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

    It also prints what it cannot pin. Gate J's third condition is not evaluable
    on that artifact, whose 53 exclusions predate the barrier field, and stage G2
    is pinned only in the half needing no source bytes, since the pinned RFCs are
    deliberately not in this repository. A self-test that skipped either in
    silence would be reporting the absence of a check as the success of one.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import threading
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
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
    "B7": "entailed by the model or by a named sibling row",
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


# Directories the operating system may reclaim without asking. A run is a
# multi-hour experimental record, so losing one to a reboot is data loss, not an
# inconvenience: an RFC 4648 run died exactly this way, with the whole
# /private/tmp/<session> tree recreated at boot and eight stages of agent work
# gone with it. Nothing about the run is recoverable afterwards, so the check has
# to happen before the first stage rather than as advice in the docstring.
#
# /var/tmp is deliberately absent. The FHS requires it to survive reboots, which
# makes it a legitimate home for a long run. Only roots that are actually cleared
# belong here; listing more would train the operator to pass the override.
VOLATILE_ROOTS = ("/tmp", "/private/tmp", "/var/folders", "/private/var/folders")


def require_durable_workdir(workdir: Path, allow: bool) -> None:
    """STOP if the run directory sits somewhere the OS may wipe."""
    roots = {Path(r).resolve() for r in VOLATILE_ROOTS}
    roots.add(Path(tempfile.gettempdir()).resolve())
    for r in sorted(roots):
        if workdir == r or r in workdir.parents:
            if allow:
                log(f"WARNING: {workdir} is under {r}; this run may not survive a "
                    "reboot (--allow-volatile-workdir was passed)")
                return
            raise StopCondition(
                f"--workdir {workdir} is under {r}, which the OS may clear at any "
                "time; a reboot has already destroyed one run this way. The run "
                "directory IS the experimental record, so put it somewhere "
                "durable AND outside this repository, e.g. ~/rfc-swarm-runs/"
                "<name>: inside the repo it would sit beside the committed "
                "records of earlier runs, which are worked answers agents must "
                "not see. Pass --allow-volatile-workdir if this run really is "
                "throwaway.")


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
            try:
                rc = subprocess.run(cmd, cwd=workdir, shell=True,
                                    stdin=subprocess.DEVNULL, stdout=so, stderr=se,
                                    env=env, timeout=self.timeout,
                                    check=False).returncode
            except subprocess.TimeoutExpired:
                # A budget overrun is a stage FAILURE, not a crash. Left
                # unhandled it propagated out of main() as a traceback, so the
                # stage recorded nothing, the manifest was left mid-run, and the
                # partial work in the agent's directory looked like debris rather
                # than a resumable state.
                raise StopCondition(
                    f"agent[{label}] exceeded its {self.timeout}s budget. Its "
                    f"partial work is in {workdir}. Re-run this stage with a "
                    "larger --timeout, or treat the overrun as a finding.")
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
        # N0 is admissible. The rule set is authored per target by stage C, and
        # the driver has no standing to dictate where its numbering starts: this
        # pattern demanded N1 only because the first run's rubric happened to
        # begin there. RFC 6455's rubric opens with "N0. The document's own
        # declaration", its extractor applied N0 to 28 of 462 rows, and the run
        # died on a complete and valid census after nineteen minutes of work.
        # Third instance of the same defect, after reconcile.py's source names
        # and rfc_coverage.py's tag prefix: a tool written during one run
        # hardcoding that run's incidental conventions as though they were the
        # format.
        require(re.match(r"^N\d+$", str(r["rule"])),
                f"{label}: row {r['id']} has rule {r['rule']!r}, expected N followed "
                "by digits (N0 included; stage C authors the rule set)")
    doc.setdefault("counts", {})
    doc["counts"] = {"normative": len(doc["normative"]),
                     "excluded": len(doc["excluded"])}
    return doc


# Words that can carry a declared strength. RFC 2119 pairs several of them as
# equivalents, and a pre-2119 RFC uses the lowercase forms, so a census may
# legitimately declare "must" for a clause whose word is "shall" or "required".
_STRENGTH_FAMILY: dict[str, tuple[str, ...]] = {
    "must": ("must", "shall", "required"),
    "must not": ("must not", "shall not"),
    "shall": ("shall", "must"),
    "required": ("required", "must"),
    "should": ("should", "recommended"),
    "should not": ("should not", "not recommended"),
    "recommended": ("recommended", "should"),
    "may": ("may", "optional", "can"),
    "optional": ("optional", "may"),
}


def check_audit(doc: Any, expected: list[str]) -> list[dict[str, Any]]:
    """Validate stage G2's catalogue: one verdict per subject, no silent drops.

    Section 7 says a delegated stage producing a catalogue for the driver to
    evaluate MUST NOT perform that evaluation itself, so the agent returns
    verdicts and evidence and the driver decides what halts. A missing cid is a
    hard failure rather than an abstention: an audit that may quietly omit its
    hardest row reports the same thing as one that found nothing.
    """
    items: Any = doc["audited"] if isinstance(doc, dict) and "audited" in doc else doc
    require(isinstance(items, list), "audit: expected an 'audited' list")
    seen: dict[str, dict[str, Any]] = {}
    for i, v in enumerate(items):
        require(isinstance(v, dict), f"audit: audited[{i}] is not an object")
        cid = str(v.get("cid", ""))
        require(cid in expected,
                f"audit: verdict for {cid!r}, which was not among the subjects")
        require(cid not in seen, f"audit: {cid} has two verdicts")
        require(v.get("verdict") in ("matches", "misreads"),
                f"audit: {cid} has verdict {v.get('verdict')!r}, expected "
                "'matches' or 'misreads'")
        if v["verdict"] == "misreads":
            for k in ("quote_phrase", "reason_phrase"):
                require(isinstance(v.get(k), str) and v[k].strip(),
                        f"audit: {cid} is flagged and carries no {k}. A flag has to "
                        "show the words it rests on, from both sides.")
        seen[cid] = v
    missing = [c for c in expected if c not in seen]
    require(not missing,
            f"audit: no verdict for {len(missing)} subject(s): {missing[:8]}. "
            "Every subject gets a verdict; silence is not a pass.")
    return [seen[c] for c in expected]


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
    semantic_retries: int = 3
    protocol_retries: int = 5
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


def _provision_reference(ctx: Ctx, wd: Path) -> None:
    """Put the LANGUAGE reference in an agent's directory.

    Stages H, K, M and N ask an agent to write LLMLL, and an agent that has
    never seen the language cannot. This is the tool manual, not the answer:
    LLMLL.md and the JSON-AST schema say what the language is, and neither says
    anything about the target RFC. The same channel `prepare_run.py` gives the
    minimal-agent harness.

    Deliberately NOT provisioned: anything under examples/, which is where prior
    worked instances (including their contracts and inventories) live.
    """
    for src in (REPO / "LLMLL.md", REPO / "docs" / "llmll-ast.schema.json"):
        if src.exists():
            shutil.copy2(src, wd / src.name)


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
    whose obligation is entailed by the declared types or by a named sibling row
    is B7 (excluded), never counted as carried, because it carries no
    verification evidence of its own.

    B7 formerly read "no mutant can exercise it". That test is undecidable in
    general and a probe showed it false on the RFC 4648 row that fired gate J, so
    it now requires an entailment the disposition names.
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


# The floor a citation's token coverage must clear for it to count as resolving
# to the pinned bytes at all. Measured, not chosen: over the 113 RFC 1350 rows of
# the committed TFTP census, every true citation scores >= 0.875, and the same
# quotes scored against 6655 same-width spans elsewhere in the file score <= 0.500
# at the 99th percentile, mean 0.086. The band [0.833, 0.875] is empty. A wrong
# span CAN still score high when the quote is short and made of common words
# (12 of 6655 reached 0.7), so this catches a citation that plainly does not
# resolve and is not a detector of subtle misplacement; stated because a gate
# whose miss rate is undisclosed gets trusted for more than it does.
CITATION_RESOLVES_AT = 0.5


def _audit_tokens(s: str) -> list[str]:
    """Alphanumeric tokens, lowercased. Punctuation and layout are dropped.

    Deliberately coarse. An RFC census legitimately quotes an elision ("A ... B")
    and legitimately flattens a multi-line packet diagram onto one line, and a
    substring test calls both of those a broken citation: on the TFTP census it
    fired on 22 of 113 correct rows. Tokens survive both.
    """
    return [t for t in "".join(c if c.isalnum() else " " for c in s.lower()).split()]


def _span_coverage(quote: str, span_text: str) -> float:
    """Fraction of the quote's tokens the cited span actually supplies.

    A bag, not a set: a quote repeating a word needs the span to repeat it too.
    """
    q = _audit_tokens(quote)
    if not q:
        return 1.0
    have: dict[str, int] = {}
    for t in _audit_tokens(span_text):
        have[t] = have.get(t, 0) + 1
    hit = 0
    for t in q:
        if have.get(t, 0) > 0:
            have[t] -= 1
            hit += 1
    return hit / len(q)


def _pinned_sources(ctx: Ctx) -> dict[str, list[str]]:
    """Map each pinned file's normalised name to its lines, split as stage A read them.

    Split on newline only, matching `_sources_text`: a census cites line numbers
    produced by that numbering, and splitlines() would treat an RFC's form-feed
    page breaks as extra line boundaries and shift every span after page one.

    Names are normalised rather than matched literally because a census writes
    "RFC1350" or "RFC 1350" for a file named `rfc1350.txt`. Spec section 7 forbids
    validation that depends on one document's conventions, and the two tools that
    hardcoded the first run's names both went on to report zeros on the second.
    """
    out: dict[str, list[str]] = {}
    for f in sorted((ctx.workdir / "00-source").glob("*.txt")):
        key = "".join(c for c in f.stem.lower() if c.isalnum())
        require(key not in out,
                f"stage G2: two pinned files normalise to {key!r}; the citation "
                "for either would be ambiguous")
        out[key] = f.read_text(encoding="utf-8", errors="replace").split("\n")
    require(out, "stage G2: no pinned RFC text under 00-source; run stage A first")
    return out


def stage_G2_audit(ctx: Ctx) -> None:
    """Check every citation against the bytes stage A pinned (spec sections 7, 14).

    Section 7 makes the driver validate a delegated output against its declared
    SHAPE, which a reason that misreads its own quote satisfies perfectly.
    Section 14 pins the source and requires later stages to read it, and nothing
    checked that they did. On RFC 4648 one disposition reason moved a positional
    qualifier out of an `unless` exception and into the prohibition, and it was a
    person reading three lines of the pinned file who caught it, after the run.

    The stage is split by what a machine can decide.

    MECHANICAL, and a STOP: the cited source resolves to a pinned file, the span
    lies inside it, and the quote's tokens come from that span. These cannot be
    wrong about a correct row.

    MECHANICAL, and REPORTED: a span that is nearly right, and a declared
    normative strength absent from its own quote. Both fire on correct input. Six
    TFTP rows cite a span one line short of their quote, and three cite RFC 1123's
    requirements-summary table, where the strength is a column position rather
    than a word. Failing closed on either would demand a correct row be mangled,
    which is the reasoning DRIFT-DOC-4 records for staying advisory.

    DELEGATED: whether a stated reason matches the clause it cites. That is a
    reading, so an agent does it and the driver evaluates the catalogue, per
    section 7. A flag must carry the phrase it relies on from each side, and the
    driver checks those phrases occur; a flag whose evidence is not in the
    artifact is an assertion, and section 6 now forbids a gate to rest on one.
    """
    sources = _pinned_sources(ctx)
    # The same spine stages F and G read. Citations live here; the dispositioned
    # rows carry only cid, class, disposition, barrier and reason.
    spine = read_json(ctx.workdir / "04-reconcile" / "data"
                      / "extraction-a.json")["normative"]
    cite = {str(r.get("cid") or r["id"]): r for r in spine}
    rows = read_json(ctx.workdir / "06-disposition"
                     / "inventory-dispositioned.json")["rows"]

    unresolved: list[dict[str, Any]] = []
    near_miss: list[dict[str, Any]] = []
    strength_absent: list[dict[str, Any]] = []
    uncited = [r["cid"] for r in rows if r["cid"] not in cite]

    for r in rows:
        c = cite.get(r["cid"])
        if c is None:
            continue
        key = "".join(ch for ch in str(c["source"]).lower() if ch.isalnum())
        lines = sources.get(key)
        if lines is None:
            unresolved.append({"cid": r["cid"], "why": "source",
                               "detail": f"cites source {c['source']!r}, which is "
                                         f"none of the pinned files {sorted(sources)}"})
            continue
        ls, le = int(c["line_start"]), int(c["line_end"])
        if not 1 <= ls <= le <= len(lines):
            unresolved.append({"cid": r["cid"], "why": "span",
                               "detail": f"cites {c['source']} L{ls}-{le}, and the "
                                         f"pinned file has {len(lines)} lines"})
            continue
        cov = round(_span_coverage(c["quote"], " ".join(lines[ls - 1:le])), 4)
        if cov < CITATION_RESOLVES_AT:
            unresolved.append({"cid": r["cid"], "why": "quote", "coverage": cov,
                               "detail": f"{c['source']} L{ls}-{le} supplies {cov:.0%} "
                                         "of the quote's tokens"})
        elif cov < 1.0:
            near_miss.append({"cid": r["cid"], "coverage": cov,
                              "cited": f"{c['source']} L{ls}-{le}"})
        strength = str(c.get("strength", "")).strip().lower()
        if strength and strength not in ("declarative", "none", "n/a"):
            q = " ".join(str(c["quote"]).lower().split())
            if not any(w in q for w in _STRENGTH_FAMILY.get(strength, (strength,))):
                strength_absent.append({"cid": r["cid"], "strength": strength,
                                        "quote": str(c["quote"])[:120]})

    log(f"  citations checked against the pinned bytes: {len(rows) - len(uncited)}"
        f" of {len(rows)} rows")
    log(f"  unresolved: {len(unresolved)}   span nearly right: {len(near_miss)}"
        f"   declared strength not in its own quote: {len(strength_absent)}")

    # Judgment half. Exactly the rows the gate reads: a core row, and any row
    # excluded under a barrier. Those are the inputs to stage J's two conditions.
    audit_ids = sorted({r["cid"] for r in rows
                        if r.get("core") or r["disposition"] == "Dispositioned out"}
                       & set(cite))
    subjects = [{"cid": i, "quote": cite[i]["quote"],
                 "cited": f"{cite[i]['source']} L{cite[i]['line_start']}"
                          f"-{cite[i]['line_end']}",
                 "obligation": cite[i].get("obligation", ""),
                 "disposition": next(r["disposition"] for r in rows if r["cid"] == i),
                 "reason": next(r["reason"] for r in rows if r["cid"] == i)}
                for i in audit_ids]
    out = ctx.agent.run(ctx.dir("06b-audit"),
                        ctx.prompt("stage-G2-audit.md",
                                   rfc_text=_sources_text(ctx),
                                   subjects=json.dumps(subjects, indent=1)),
                        "audit.json", "audit")
    verdicts = check_audit(read_json(out), audit_ids)

    misread = [v for v in verdicts if v["verdict"] == "misreads"]
    for v in misread:
        c, r = cite[v["cid"]], next(x for x in rows if x["cid"] == v["cid"])
        require(" ".join(v["quote_phrase"].lower().split())
                in " ".join(str(c["quote"]).lower().split()),
                f"STOP (stage G2): the flag on {v['cid']} quotes "
                f"{v['quote_phrase']!r} from the clause, and that phrase is not in "
                "the pinned quote. A flag whose evidence is not in the artifact is "
                "an assertion, not a finding.")
        require(" ".join(v["reason_phrase"].lower().split())
                in " ".join(str(r["reason"]).lower().split()),
                f"STOP (stage G2): the flag on {v['cid']} quotes "
                f"{v['reason_phrase']!r} from the reason, and that phrase is not in "
                "the recorded reason. A flag whose evidence is not in the artifact "
                "is an assertion, not a finding.")
        v["core"] = bool(next(x for x in rows if x["cid"] == v["cid"]).get("core"))

    report = {
        "rows": len(rows),
        "citations_checked": len(rows) - len(uncited),
        "uncited_rows": uncited,
        "unresolved_citations": unresolved,
        "span_nearly_right": near_miss,
        "declared_strength_absent_from_quote": strength_absent,
        "reasons_audited": len(audit_ids),
        "reasons_flagged": misread,
        "note": "unresolved_citations is a STOP. span_nearly_right and "
                "declared_strength_absent_from_quote are reported and NOT "
                "thresholded: both fire on correct rows.",
    }
    write_json(ctx.d("06b-audit", "audit.json"), report)

    require(not uncited,
            f"STOP (stage G2): {len(uncited)} dispositioned rows cite no census "
            f"row: {uncited[:8]}. A disposition with no citation cannot be checked "
            "against the pinned bytes at all.")
    require(not unresolved,
            "STOP (stage G2): citations that do not resolve to the pinned bytes: "
            + json.dumps(unresolved[:6])
            + ". Section 14 pins the source so that every later stage reads it; a "
              "citation that resolves to nothing was not read from it.")
    flagged_core = [v["cid"] for v in misread if v.get("core")]
    require(not flagged_core,
            f"STOP (stage G2): characteristic-core rows whose stated reason "
            f"misreads the clause it cites: {flagged_core}. Stage J decides the "
            "target from core membership and disposition, and section 6 forbids a "
            "gate condition to rest on an input carrying no evidence. Correct the "
            "reason, then let the gate rule on it.")
    if misread:
        log(f"  reasons flagged (none core, recorded not fatal): "
            f"{[v['cid'] for v in misread]}")
    log("  artifact audit PASS")


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
    _provision_reference(ctx, wd)
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
    wd = ctx.dir("10-roots")
    _provision_reference(ctx, wd)
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

    Coordination is only through checkout / patch. Each agent sees its checkout
    brief and nothing else: no reference solution, no other agent's attempt, no
    hint. Everything it knows arrives through the compiler.

    Two retry budgets, counted separately, because conflating them lets
    contention eat an agent's error budget:

      semantic  the fill did not verify. The agent is re-invoked with the
                compiler's error text and nothing else added.
      protocol  the patch was rejected because another agent moved the file
                first (compare-and-swap on the brief's source_hash). The SAME
                body is re-applied against a fresh checkout; no agent call.

    Agents think in parallel; patches serialize, because the CAS is a real
    mutual-exclusion point on one file and pretending otherwise would just
    convert conflicts into lost work.

    Per-fill bar: verify SAFE, the filled function body-faithful, not flagged
    termination_unverified. A hole that exhausts its semantic budget is a
    FINDING, routed to the compiler team or back to the inventory as a scoping
    error. It is never an occasion for a hint.
    """
    roots = ctx.workdir / "10-roots" / "roots.llmll"
    wave = ctx.dir("12-wave")
    tree = wave / "roots.ast.json"
    if not tree.exists() or ctx.force:
        shutil.copy2(roots, wave / "roots.llmll")
        p = subprocess.run([ctx.llmll, "build", str(wave / "roots.llmll"),
                            "--emit", "-o", str(wave)],
                           capture_output=True, text=True, check=False)
        require(tree.exists(), f"stage M: could not emit the AST\n{p.stdout}{p.stderr}")
    holes = _ast_holes(tree)
    require(holes, "stage M: no holes to fill")
    log(f"  {len(holes)} holes, {ctx.wave_agents} concurrent agents")

    patch_lock = threading.Lock()
    results: list[dict] = []

    def fill(item: tuple[int, tuple[str, str]]) -> dict:
        i, (pointer, fn) = item
        wd = ctx.dir("12-wave", f"agent-{i:02d}-{fn}")
        # A PRISTINE scratch copy so the agent can self-check before submitting.
        # Pristine matters: it is the frozen root surface with every hole still a
        # hole, so it carries no other agent's body. Handing over the live tree
        # would let one agent read another's attempt and destroy the blindness
        # the wave exists to demonstrate. Discovered by running a real agent,
        # which correctly refused to go looking for a tree it had not been given
        # and therefore could not verify its own work.
        shutil.copy2(wave / "roots.llmll", wd / "scratch.llmll")
        _provision_reference(ctx, wd)
        errors = ""
        for attempt in range(1, ctx.semantic_retries + 1):
            brief = _checkout(ctx, tree, pointer, wd)
            if brief is None:
                return {"hole": fn, "pointer": pointer, "status": "checkout-failed"}
            try:
                ctx.agent.run(wd, ctx.prompt("stage-M-fill.md", brief=json.dumps(brief, indent=1),
                                             hole=fn, llmll=ctx.llmll,
                                             errors=errors or "(first attempt)"),
                              "body.json", f"fill-{fn}#{attempt}")
            except StopCondition as e:
                errors = str(e)
                _release(ctx, tree, brief["token"])
                continue
            body = read_json(wd / "body.json")
            ok, err = _apply(ctx, tree, brief, body, patch_lock, wd)
            if not ok:
                errors = err
                continue
            v = _verify_fn(ctx, tree, fn)
            if v["ok"]:
                log(f"  fill {fn}: accepted (attempt {attempt})")
                return {"hole": fn, "pointer": pointer, "status": "filled",
                        "attempts": attempt}
            # a wrong body never stays in the tree: put the hole back so the next
            # attempt starts clean and no sibling reads a rejected fill
            errors = v["detail"]
            _revert(tree, pointer, brief["hole_node"], patch_lock)
            _release(ctx, tree, brief["token"])
        return {"hole": fn, "pointer": pointer, "status": "finding",
                "attempts": ctx.semantic_retries, "last_error": errors[-1500:]}

    with concurrent.futures.ThreadPoolExecutor(max_workers=ctx.wave_agents) as ex:
        results = list(ex.map(fill, enumerate(holes)))

    v = _verify(ctx, tree, strict=True)
    write_json(wave / "wave.json", {"fills": results, "whole_tree": v})
    filled = [r for r in results if r["status"] == "filled"]
    findings = [r for r in results if r["status"] != "filled"]
    log(f"  filled {len(filled)}/{len(holes)}; whole tree: "
        f"{'SAFE' if v['safe'] else 'NOT SAFE'}")
    if findings:
        # Report the ACTUAL failure mode. Lumping checkout/harness faults under
        # "exhausted budget" reads as an agent that could not do the work, when
        # the agent may never have been asked. Only `finding` means the budget
        # was genuinely spent.
        by_kind: dict[str, list[str]] = {}
        for r in findings:
            by_kind.setdefault(r["status"], []).append(r["hole"])
        for status, holes in sorted(by_kind.items()):
            label = ("exhausted its retry budget; routed, never hinted"
                     if status == "finding"
                     else f"NOT a finding: {status} (harness fault, no budget spent)")
            log(f"  {label}: " + ", ".join(holes))


def _ast_holes(tree: Path) -> list[tuple[str, str]]:
    """Every hole body in the AST, as (RFC-6901 pointer, function name)."""
    doc = read_json(tree)
    out = []
    for i, st in enumerate(doc.get("statements", [])):
        body = st.get("body")
        if isinstance(body, dict) and str(body.get("kind", "")).startswith("hole"):
            out.append((f"/statements/{i}/body", st.get("name", f"stmt{i}")))
    return out


def _checkout(ctx: Ctx, tree: Path, pointer: str, wd: Path) -> dict | None:
    p = subprocess.run([ctx.llmll, "checkout", str(tree), pointer],
                       capture_output=True, text=True, check=False)
    try:
        brief = json.loads(p.stdout)
    except json.JSONDecodeError:
        (wd / "checkout.err").write_text(p.stdout + p.stderr, encoding="utf-8")
        return None
    # keep the hole node so the patch can assert it (CAS) and so a failed fill
    # can be reverted without guessing what was there
    doc = read_json(tree)
    node = doc
    for seg in pointer.strip("/").split("/"):
        node = node[int(seg)] if seg.isdigit() else node[seg]
    brief["hole_node"] = node
    (wd / "BRIEF.json").write_text(json.dumps(brief, indent=1), encoding="utf-8")
    return brief


def _release(ctx: Ctx, tree: Path, token: str) -> None:
    """Give the checkout lock back. Skipping this is what turns a recoverable
    stale-context rejection into a permanently wedged hole."""
    subprocess.run([ctx.llmll, "checkout", str(tree), "--release", token],
                   capture_output=True, text=True, check=False)


def _apply(ctx: Ctx, tree: Path, brief: dict, body: Any,
           lock: "threading.Lock", wd: Path) -> tuple[bool, str]:
    """Submit the agent's body, atomically, against a FRESH checkout.

    The compare-and-swap is per-FILE, not per-hole: `patch` rejects any request
    whose brief predates the current source (`PatchAuthError: obligation context
    is stale`). With N agents on one tree, the first patch to land therefore
    invalidates every other outstanding brief, however different the holes are.
    Measured, not assumed: two holes checked out concurrently, first patch
    PatchSuccess, second PatchAuthError.

    So submission does not reuse the brief the agent worked from. Under the lock
    it releases that token, takes a fresh checkout of the same pointer, and
    builds the patch from the fresh token and the CURRENT hole node. The body is
    unaffected, because it was authored against the contract, which does not
    change when a sibling hole is filled. No agent call is involved, which is
    why these retries are budgeted separately from semantic ones.
    """
    err = ""
    for _ in range(ctx.protocol_retries):
        with lock:
            _release(ctx, tree, brief["token"])
            fresh = _checkout(ctx, tree, brief["pointer"], wd)
            if fresh is None:
                return False, "could not re-checkout for submission"
            brief = fresh
            req = {"token": brief["token"],
                   "patch": [{"op": "test", "path": brief["pointer"],
                              "value": brief["hole_node"]},
                             {"op": "replace", "path": brief["pointer"],
                              "value": body}]}
            rp = wd / "patch-request.json"
            write_json(rp, req)
            p = subprocess.run([ctx.llmll, "patch", str(tree), str(rp)],
                               capture_output=True, text=True, check=False)
            if p.returncode == 0:
                return True, ""
            err = (p.stdout + p.stderr)[-2000:]
            # `patch` also runs the verifier, so a rejection here is usually the
            # fill being wrong rather than a race. Only a stale context is worth
            # retrying without re-consulting the agent.
            if "stale" not in err and "PatchAuthError" not in err:
                return False, err
    return False, err


def _revert(tree: Path, pointer: str, hole_node: Any, lock: "threading.Lock") -> None:
    """Put the hole back after a rejected fill, so the next attempt starts clean
    and a failed hole never leaves a wrong body in the tree."""
    with lock:
        doc = read_json(tree)
        node = doc
        segs = pointer.strip("/").split("/")
        for seg in segs[:-1]:
            node = node[int(seg)] if seg.isdigit() else node[seg]
        last = segs[-1]
        node[int(last) if last.isdigit() else last] = hole_node
        write_json(tree, doc)


def _verify_fn(ctx: Ctx, tree: Path, fn: str) -> dict:
    """The per-fill bar, evaluated for THIS function only.

    Deliberately NOT `--strict-verified-core`: that flag hard-errors when ANY
    function in the module falls back, and during a wave every hole not yet
    filled falls back by construction. Gating a fill on it would reject a
    correct body because its siblings are unfinished (the strict-sibling wall)
    and would make the whole wave order-dependent.

    So the bar is read per function: the module must not be refuted, and THIS
    function must appear in the body-faithful set. The whole-tree
    `--strict-verified-core` check still runs once at the end of the wave, when
    every hole is filled and it means what it says.
    """
    p = subprocess.run([ctx.llmll, "verify", str(tree)],
                       capture_output=True, text=True, check=False)
    out = p.stdout + p.stderr
    safe = "SAFE" in out
    refuted = f"body verification of '{fn}'" in out or "refuted" in out.lower()
    faithful = fn in _faithful(out)
    ok = safe and faithful and not refuted
    return {"ok": ok, "safe": safe, "body_faithful": faithful, "refuted": refuted,
            "detail": out[-3000:]}


def _faithful(out: str) -> set[str]:
    m = re.search(r"body-faithful:\s*(.+)", out)
    return {s.strip() for s in m.group(1).split(",")} if m else set()


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
    _provision_reference(ctx, wd)
    tree = ctx.workdir / "12-wave" / "roots.ast.json"
    out = ctx.agent.run(wd, ctx.prompt("stage-N-mutants.md",
                                       tree=tree.read_text(encoding="utf-8"),
                                       prereg=(ctx.workdir / "08-prereg"
                                               / "PRE-REGISTRATION.md"
                                               ).read_text(encoding="utf-8")),
                        "mutants.json", "mutants")
    matrix = []
    for m in read_json(out):
        # An entry with no file is legitimate: the taxonomy keeps a pre-registered
        # mutant that turned out to be UNWRITABLE (nothing in the frozen surface
        # instantiates the behaviour it would perturb) rather than dropping it,
        # so the denominator stays honest. Score it as unwritable, not as a kill.
        if m.get("unwritable") or not m.get("file"):
            matrix.append({"name": m.get("name"), "good_twin": bool(m.get("good_twin")),
                           "verdict": "unwritable", "as_expected": True,
                           "reason": m.get("reason") or m.get("note")})
            log(f"  {m.get('name')}: unwritable (kept in the denominator)")
            continue
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
    survivors = [m["name"] for m in matrix
                 if not m["good_twin"] and m.get("verdict") not in ("refuted", "unwritable")]
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
    # Before H, not after J. A citation that does not resolve should stop the run
    # before it spends forty-five minutes on feasibility probes, and stage J's two
    # conditions read the dispositions this stage audits.
    Stage("G2", "artifact audit", "gate", stage_G2_audit,
          ("06b-audit/audit.json",)),
    Stage("H", "feasibility probes", "agent", stage_H_feasibility,
          ("07-feasibility/feasibility.json",)),
    Stage("I", "pre-registration", "agent", stage_I_prereg,
          ("08-prereg/PRE-REGISTRATION.md",)),
    Stage("J", "the gate", "gate", stage_J_gate, ("09-gate/gate.json",)),
    Stage("K", "root contract authoring", "agent", stage_K_contracts,
          ("10-roots/roots.llmll",)),
    # ROOTS.txt is declared, not just the lint report: it is the provenance
    # monopoly list and an INPUT to the lint, so it must be covered by the §5
    # integrity check like any other output of this stage.
    Stage("L", "coverage lint and freeze", "gate", stage_L_coverage,
          ("11-freeze/rfc-cov-1.txt", "11-freeze/ROOTS.txt")),
    # roots.ast.json is THE implementation. Declaring only wave.json left the
    # artifact that matters uncovered by the §5 integrity check, which is how a
    # hand-edited body entered the ARP tree unnoticed.
    Stage("M", "the swarm", "agent", stage_M_wave,
          ("12-wave/wave.json", "12-wave/roots.ast.json")),
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

    # Gate J has THREE conditions and this artifact can only exercise two.
    #
    # The closed barrier list postdates the TFTP run, so none of its 53
    # exclusions carries a `barrier` field: the per-barrier tally exists as prose
    # in examples/tftp_rfc1350/VERIFICATION_SCOPE.md and never as data. Replayed
    # against the shipped driver this artifact would fail check_dispositioned and
    # then STOP at gate J's third condition.
    #
    # Asserting the zero is the point. Skipping the condition let the self-test
    # report a green mechanical spine while the one condition that would fire on
    # its own pinned data went unevaluated, which is the shape of a gate kept
    # green by its own blind spot. If the TFTP ledger ever gains barriers this
    # assertion fails and forces the pin to be re-taken.
    excluded = [r for r in rows if r["disposition"] == "Dispositioned out"]
    check("excluded rows", len(excluded), 53)
    check("excluded rows carrying a barrier from the closed list",
          sum(1 for r in excluded if r.get("barrier") in BARRIERS), 0)
    print("     NOT EXERCISED: gate J's third condition (exclusions outside the")
    print("     closed barrier list). This artifact predates the barrier field,")
    print("     so a green self-test says nothing about that condition.")

    print("self-test: the artifact audit (stage G2) against the committed census")
    # Only the half that needs no source bytes. The pinned RFCs are deliberately
    # not in this repository, so the citation checks cannot be replayed here; the
    # strength check reads the census row alone and can.
    canon = read_json(data / "inventory-merged.json")["canonical"]
    absent = [c["cid"] for c in canon
              if (s := str(c.get("strength", "")).strip().lower())
              and s != "declarative"
              and not any(w in " ".join(str(c["quote"]).lower().split())
                          for w in _STRENGTH_FAMILY.get(s, (s,)))]
    check("canonical rows", len(canon), 124)
    check("declared strength absent from its own quote", absent,
          ["T117", "T118", "T119"])
    print("     Those three cite RFC 1123's requirements-summary table, where the")
    print("     strength is a column position rather than a word. They are why")
    print("     this check reports and never halts.")

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

# How long a live driver may write NOTHING anywhere in the workdir before the
# quiet is worth reporting. Generous on purpose: an agent can think for minutes
# between tokens, and a false alarm here is what the previous heuristic produced.
STALL_SECONDS = 1800


def newest_activity(workdir: Path) -> tuple[float, Path | None]:
    """Most recent mtime anywhere under the workdir, and the file carrying it.

    run.log is the WRONG liveness signal and reporting it as one flagged a
    perfectly healthy run as stale. The driver writes run.log between stages;
    during an agent stage it is blocked inside subprocess.run and cannot write
    anything at all. Most stages are agent stages, so a frozen log is the NORMAL
    condition of a working run, and with --timeout 7200 it is normal for hours.

    What does move is the agent's own output: subprocess.run hands the child's
    stdout and stderr straight to agent.stdout.log and agent.stderr.log, so those
    files tick as the agent produces text. The newest mtime over the whole tree
    therefore watches the agent work, which is the question being asked.
    """
    newest, where = 0.0, None
    for root, _dirs, files in os.walk(workdir, onerror=lambda _e: None):
        for fn in files:
            p = Path(root) / fn
            try:
                m = p.stat().st_mtime
            except OSError:
                continue
            if m > newest:
                newest, where = m, p
    return newest, where


def show_status(workdir: Path) -> int:
    """Report what a run is ACTUALLY doing, from four independent signals.

    Exists because "I launched it" is not evidence it is running, and inferring
    liveness from a launch is how this reported a dead pipeline as live twice.
    The signals:

      process   is a driver bound to THIS workdir alive right now
      log       when did run.log last advance (between stages only, see below)
      activity  when did ANY file under the workdir last change; a live process
                writing nothing for STALL_SECONDS is stuck, and that looks
                identical to progress from the outside
      manifest  which stages actually completed, and which one stopped

    None alone is sufficient, which is why all four are printed.
    """
    log_path = workdir / "run.log"
    man_path = workdir / "MANIFEST.json"

    # Liveness by STRUCTURE, not by pattern. Three attempts got this wrong:
    #   `pgrep -af`     -a is GNU; on BSD it returns bare PIDs, so nothing matched
    #   substring match the shell wrapper of this very command matched itself
    #   interpreter regex the real binary is .../MacOS/Python, capital P
    # A driver is a process whose FIRST token is an executable path and whose
    # second token is the script. That is true of the driver and of nothing else,
    # including `claude -p <prompt mentioning the script>` and any grep for it.
    alive = False
    try:
        out = subprocess.run(["ps", "-axo", "pid=,args="],
                             capture_output=True, text=True, check=False).stdout
        me = os.getpid()
        for ln in out.splitlines():
            parts = ln.split(None, 1)
            if len(parts) < 2 or not parts[0].isdigit():
                continue
            pid, args = int(parts[0]), parts[1]
            # Skip THIS process: `--status` is itself the script, run against this
            # very workdir, so without this it reports itself as a live run and
            # every query answers RUNNING. Skip other --status queries too.
            if pid == me or "--status" in args:
                continue
            tok = args.split()
            if len(tok) >= 2 and tok[1].endswith("rfc_to_implementation.py") \
               and "/" in tok[0] and str(workdir) in args:
                alive = True
                break
    except Exception:
        pass

    print(f"workdir : {workdir}")
    print(f"process : {'RUNNING' if alive else 'not running'}")

    def ago(sec: float) -> str:
        return f"{sec:.0f}s" if sec < 120 else f"{sec / 60:.0f}m"

    now = time.time()
    if log_path.exists():
        print(f"log     : last advanced {ago(now - log_path.stat().st_mtime)} ago"
              "   (frozen during an agent stage is NORMAL)")
    else:
        print("log     : (none)")

    newest, where = newest_activity(workdir)
    if where is None:
        print("activity: (nothing written yet)")
    else:
        idle = now - newest
        stalled = alive and idle > STALL_SECONDS
        print(f"activity: {where.relative_to(workdir)} written {ago(idle)} ago"
              + ("   <-- STALLED: process alive, workdir untouched"
                 if stalled else ""))

    if man_path.exists():
        man = read_json(man_path)
        done = man.get("stages", {})
        print("stages  :")
        for st in STAGES:
            rec = done.get(st.key)
            if rec is None:
                mark, extra = "· pending", ""
            elif rec.get("status") == "complete":
                mark, extra = "✓ complete", f"  {rec.get('seconds','?')}s"
            elif rec.get("status") == "failed":
                # Distinct from STOPPED on purpose. A stop is a verdict the
                # method reached and is a result; a failure is an accident and
                # is not. Printing both as "STOPPED" would let a crashed run be
                # read as a fired gate, which is the one confusion this whole
                # experiment cannot afford.
                mark, extra = "! FAILED", f"  {str(rec.get('detail', ''))[:90]}"
            else:
                mark, extra = "✗ STOPPED", f"  {str(rec.get('detail', ''))[:90]}"
            print(f"   {st.key} [{st.kind:10}] {st.name:<34} {mark}{extra}")
    else:
        print("stages  : (no manifest yet)")

    if log_path.exists():
        tail = log_path.read_text(errors="replace").splitlines()[-3:]
        print("last    :")
        for ln in tail:
            print(f"   {ln}")
    return 0


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
            f"  {s.key:2}  [{s.kind:10}] {s.name}" for s in STAGES))
    ap.add_argument("--rfc-url", help="URL of the RFC as verbatim text")
    ap.add_argument("--amend-url", action="append", default=[],
                    help="URL of an amending RFC (repeatable)")
    ap.add_argument("--workdir", type=Path, help="run directory")
    ap.add_argument("--agent-cmd",
                    help="shell command template; {prompt} {out} {workdir} expand")
    ap.add_argument("--llmll-cmd", default=os.environ.get("LLMLL_CMD", "llmll"))
    ap.add_argument("--wave-agents", type=int, default=4)
    ap.add_argument("--semantic-retries", type=int, default=3,
                    help="per-hole retries after a failed verify (agent re-invoked)")
    ap.add_argument("--protocol-retries", type=int, default=5,
                    help="per-hole retries after a patch CAS conflict (no agent call); "
                         "budgeted separately so contention cannot eat the error budget")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--only", help="run only these stages, e.g. A,B,D")
    ap.add_argument("--from", dest="from_stage", help="start at this stage")
    ap.add_argument("--force", action="store_true", help="re-run completed stages")
    ap.add_argument("--self-test", action="store_true",
                    help="replay committed TFTP data through the mechanical stages")
    ap.add_argument("--audit-blindness", action="store_true",
                    help="re-check that stage D's extractors were isolated")
    ap.add_argument("--status", action="store_true",
                    help="report whether a run is alive, advancing, and how far it got")
    ap.add_argument("--allow-volatile-workdir", action="store_true",
                    help="permit a workdir under /tmp; such a run may be lost at reboot")
    a = ap.parse_args(argv)

    if a.self_test:
        return self_test()
    if a.status:
        require(a.workdir is not None, "--status needs --workdir")
        return show_status(a.workdir.resolve())
    if a.audit_blindness:
        require(a.workdir is not None, "--audit-blindness needs --workdir")
        return audit_blindness(a.workdir)

    missing = [f for f, v in (("--rfc-url", a.rfc_url), ("--workdir", a.workdir),
                              ("--agent-cmd", a.agent_cmd)) if not v]
    if missing:
        ap.error(f"missing required argument(s): {', '.join(missing)}")

    require_durable_workdir(a.workdir.resolve(), a.allow_volatile_workdir)

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
              amend_urls=a.amend_url, wave_agents=a.wave_agents,
              semantic_retries=a.semantic_retries,
              protocol_retries=a.protocol_retries, force=a.force)
    ctx.workdir.mkdir(parents=True, exist_ok=True)
    manifest_path = ctx.workdir / "MANIFEST.json"
    manifest = read_json(manifest_path) if manifest_path.exists() else {"stages": {}}
    manifest.setdefault("rfc_url", a.rfc_url)

    for stage in STAGES:
        if stage.key not in selected:
            continue
        # Spec §5. Three conditions, not two.
        #
        # (a) the manifest RECORDS the stage complete. Artifacts alone are not
        #     evidence of success: a stage that fails AFTER writing output would
        #     otherwise be skipped next run, which is exactly how a failing
        #     RFC-COV-1 freeze gate got bypassed and the wave ran on against an
        #     unfrozen surface.
        # (b) every declared artifact is PRESENT.
        # (c) every artifact still MATCHES the digest recorded at completion.
        #     Presence is not integrity. An artifact edited after its stage
        #     recorded completion is not that stage's output, and a later stage
        #     consuming it consumes something no stage of this run produced.
        #     The digests were already being recorded and never read.
        rec = manifest["stages"].get(stage.key)
        recorded = bool(rec) and rec.get("status") == "complete"
        artifacts = all((ctx.workdir / o).exists() for o in stage.outputs)
        recorded_digests = (rec or {}).get("outputs", {})
        mismatched: list[str] = []
        if recorded and artifacts:
            for o in stage.outputs:
                want = recorded_digests.get(o)
                # a missing digest cannot match, and is treated as a mismatch:
                # an artifact whose integrity was never recorded is not evidence
                if want is None or want != sha256_file(ctx.workdir / o):
                    mismatched.append(o)
        if recorded and artifacts and not mismatched and not a.force:
            log(f"stage {stage.key} ({stage.name}): already complete, skipping")
            continue
        if mismatched:
            log(f"stage {stage.key}: artifact(s) changed since this stage recorded "
                f"completion ({', '.join(mismatched)}) — re-running. An artifact "
                "modified outside the protocol is not that stage's output.")
        elif artifacts and not recorded:
            log(f"stage {stage.key}: artifacts present but no completion record "
                "(interrupted, or a previous attempt failed) — re-running")
        log(f"stage {stage.key} [{stage.kind}] {stage.name}")
        started = time.monotonic()
        try:
            stage.fn(ctx)
        except StopCondition as e:
            log(f"STOP at stage {stage.key}: {e}")
            manifest["stages"][stage.key] = {"status": "stopped", "detail": str(e)}
            write_json(manifest_path, manifest)
            return 2
        except Exception as e:  # noqa: BLE001 — see below
            # Anything that is NOT a deliberate stop: a fetch that failed, a
            # malformed JSON file, a bug in this script. Previously these escaped
            # as a bare traceback, which left NOTHING in the manifest, so a
            # resume could not tell "stage crashed" from "stage never ran" and
            # the operator could not tell a decision from an accident. Both facts
            # are worth keeping, so record the failure AND print the traceback:
            # the manifest entry serves resume, the traceback serves debugging.
            log(f"FAILED at stage {stage.key}: {type(e).__name__}: {e}")
            traceback.print_exc()
            manifest["stages"][stage.key] = {
                "status": "failed",
                "detail": f"{type(e).__name__}: {e}",
            }
            write_json(manifest_path, manifest)
            return 3
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
    # A StopCondition raised OUTSIDE a stage (argument validation, the workdir
    # check) has no per-stage handler to catch it and would print a traceback.
    # A stop is a decision the driver made, and it should read like one; twice
    # now a deliberate halt has been indistinguishable from a crash.
    try:
        sys.exit(main())
    except StopCondition as exc:
        log(f"STOP: {exc}")
        sys.exit(2)
