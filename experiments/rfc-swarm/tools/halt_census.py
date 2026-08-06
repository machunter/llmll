#!/usr/bin/env python3
"""Write-before-halt census over the RFC-SWARM reference driver.

WHAT THIS ANSWERS. `docs/design/driver-ll-phase4-proposal.md` section 3.6 sorts
halt sites along two orthogonal axes:

  * the CLAUSE-SOURCE axis (section 3.5): a halt raised through `require_spec`
    is spec-defined and records `stopped`; a plain `require` records `failed`;

  * the ARTIFACT-STATE axis (driver-spec section 4:146-147): a stage that wrote
    some artifacts and then halted MUST record `stopped`, whatever defined the
    condition.

The table stating that census is keyed by LINE NUMBER and its keys are stale.
Section 3.5.1 already forbids line keys for the other axis, for the reason this
file exists: two of the nine spec-defined line numbers point at sites with the
opposite disposition, so a reader keying on a number lands somewhere plausible
and nothing signals the miss. This computes the census instead, keyed by
enclosing function and clause.

WHY IT IS INTERPROCEDURAL, which is the whole difficulty. The Rev 10 note that
made this owed work observed that two conditions the table files as post-write
fire inside `_pinned_sources`, a helper G2 calls BEFORE writing anything of its
own. A census that walks only the stage handler's own body cannot see them; one
that walks helpers without tracking the state at the CALL SITE reports them
against the wrong axis value. So halts are attributed to the stage whose
handler reaches them, at the write-state that holds when control arrives.

WHY THE LATTICE HAS THREE VALUES AND NOT TWO. F-19 found a source line carrying
two artifact-state dispositions, one per loop iteration: the write happens
inside the loop body, so iteration 1 reaches the halt with nothing written and
iteration 2 reaches it with the first iteration's artifact on disk. Any census
reporting one disposition per site is wrong by construction on that shape.
`MAYBE` is that case, and it is a finding rather than an imprecision.

TWO WRITE DEFINITIONS, RUN SIDE BY SIDE. driver-spec section 4:146-147 says
"wrote some artifacts". Whether that means the stage's DECLARED outputs or any
file it put on disk is a reading, not a measurement, so both are computed and
the sites where the reading changes the verdict are reported. That difference
is the eliminative content: agreement between the two tells you nothing.

Usage:  python3 experiments/rfc-swarm/tools/halt_census.py [--json]
"""
from __future__ import annotations

import argparse
import ast
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
DRIVER = REPO / "scripts" / "rfc_to_implementation.py"

HALT_HELPERS = {"require", "require_spec", "require_written"}
SPEC_DEFINED = {"require_spec"}

# Any file the process puts on disk.
WRITE_ANY = {"write_json", "write_text", "write_bytes", "copy2", "copytree"}
# The subset that plausibly lands a stage's DECLARED output. PROMPT.md, run
# logs and provisioning copies are on disk but are not what section 4:146-147
# is about; `write_json` and `write_text` to a stage's own out-path are.
WRITE_DECLARED = {"write_json", "write_text", "write_bytes"}

NO, MAYBE, YES = 0, 1, 2
LATTICE = {NO: "pre-write", MAYBE: "BOTH", YES: "post-write"}


def join(a: int, b: int) -> int:
    if a == b:
        return a
    return MAYBE


def seq(a: int, b: int) -> int:
    """State after a region whose own effect is `b`, entered at `a`."""
    if b == YES:
        return YES
    if b == NO:
        return a
    return YES if a == YES else MAYBE


class Census:
    def __init__(self, tree: ast.Module, writes: set[str],
                 declared_only: list[str] | None = None) -> None:
        self.tree = tree
        self.writes = writes
        self.declared_only = declared_only
        self.fns = {n.name: n for n in tree.body
                    if isinstance(n, ast.FunctionDef)}
        self.hits: list[dict] = []
        self._seen: dict[tuple, dict] = {}
        self._stage = "?"
        self._stack: list[str] = []

    # -- write detection -------------------------------------------------
    def _write_path(self, node: ast.Call) -> str | None:
        """The unparsed PATH expression of a write, or None if not a write.

        The two call shapes put the path in different places, and conflating
        them is how a log write reads as an artifact write: `write_json(p, doc)`
        is a Name call whose first argument is the path, while
        `p.write_text(s)` is an Attribute call whose first argument is the
        CONTENT and whose path is the attribute's value.
        """
        f = node.func
        if isinstance(f, ast.Name) and f.id in self.writes:
            return ast.unparse(node.args[0]) if node.args else ""
        if isinstance(f, ast.Attribute) and f.attr in self.writes:
            return ast.unparse(f.value)
        return None

    def _is_write(self, node: ast.Call) -> bool:
        path = self._write_path(node)
        if path is None:
            return False
        if self.declared_only is None:
            return True
        # A write counts only when its path names one of THIS stage's declared
        # outputs, or is the conventional `out` binding for them. Provisioning
        # copies, prompt files and run logs are on disk and are not what
        # driver-spec section 4:146-147 means by "wrote some artifacts".
        if path == "out" or path.startswith("out "):
            return True
        return any(base in path for base in self.declared_only)

    def _local_call(self, node: ast.Call) -> str | None:
        f = node.func
        if isinstance(f, ast.Name) and f.id in self.fns:
            return f.id
        return None

    # -- the walk --------------------------------------------------------
    def run_stage(self, letter: str, handler: str) -> None:
        self._stage = letter
        self._stack = []
        if handler in self.fns:
            self.walk_body(self.fns[handler].body, NO)

    def walk_body(self, body: list[ast.stmt], state: int) -> int:
        for stmt in body:
            state = self.walk_stmt(stmt, state)
        return state

    def walk_stmt(self, node: ast.stmt, state: int) -> int:
        if isinstance(node, ast.If):
            for e in ast.walk(node.test):
                state = self.walk_expr(e, state) if isinstance(e, ast.Call) else state
            a = self.walk_body(node.body, state)
            b = self.walk_body(node.orelse, state) if node.orelse else state
            return join(a, b)

        if isinstance(node, (ast.For, ast.AsyncFor, ast.While)):
            iter_node = getattr(node, "iter", None) or getattr(node, "test", None)
            if isinstance(iter_node, ast.expr):
                state = self.walk_expr_tree(iter_node, state)
            # Pass 1: entry state. Pass 2: entry joined with end-of-body, which
            # is the back edge. A halt visited in both passes at differing
            # states is the F-19 shape and lands as MAYBE.
            end = self.walk_body(node.body, state)
            entry2 = join(state, end)
            if entry2 != state:
                end = self.walk_body(node.body, entry2)
            after = join(state, end)
            if node.orelse:
                after = join(after, self.walk_body(node.orelse, after))
            return after

        if isinstance(node, ast.Try):
            s = self.walk_body(node.body, state)
            for h in node.handlers:
                s = join(s, self.walk_body(h.body, state))
            if node.orelse:
                s = join(s, self.walk_body(node.orelse, s))
            if node.finalbody:
                s = self.walk_body(node.finalbody, s)
            return s

        if isinstance(node, (ast.With, ast.AsyncWith)):
            return self.walk_body(node.body, state)

        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            return state  # nested definitions are not executed here

        if isinstance(node, ast.Raise):
            self.record("raise", node, state, None)
            return state

        for e in ast.iter_child_nodes(node):
            if isinstance(e, ast.expr):
                state = self.walk_expr_tree(e, state)
        return state

    def walk_expr_tree(self, node: ast.expr, state: int) -> int:
        """Evaluate calls left to right; a nested call's effect precedes the
        outer one, which is what makes `require(write_json(...))` order right."""
        for child in ast.iter_child_nodes(node):
            if isinstance(child, ast.expr):
                state = self.walk_expr_tree(child, state)
        if isinstance(node, ast.Call):
            state = self.walk_expr(node, state)
        return state

    def walk_expr(self, node: ast.Call, state: int) -> int:
        f = node.func
        if isinstance(f, ast.Name) and f.id in HALT_HELPERS:
            clause = None
            if f.id == "require_spec" and len(node.args) >= 3:
                a = node.args[2]
                if isinstance(a, ast.Constant) and isinstance(a.value, str):
                    clause = a.value
            self.record(f.id, node, state, clause)
            return state

        if self._is_write(node):
            return YES

        callee = self._local_call(node)
        if callee and callee not in self._stack and callee not in HALT_HELPERS:
            self._stack.append(callee)
            out = self.walk_body(self.fns[callee].body, state)
            self._stack.pop()
            return out
        return state

    def record(self, helper: str, node: ast.AST, state: int, clause: str | None) -> None:
        """One row per SITE, joining every state it is reached at.

        The loop fixpoint visits a body twice, so a site inside a loop is
        reached once at the entry state and once at the back-edge state.
        Appending both would report one site as two, which is the same
        per-site-enumeration error F-19 found in the table this replaces, made
        by the instrument instead of by the reader. Joining them is what turns
        "reached at NO and at YES" into the MAYBE that names the shape.
        """
        via = " > ".join(self._stack) if self._stack else "(handler)"
        key = (self._stage, via, getattr(node, "lineno", -1))
        prior = self._seen.get(key)
        if prior is not None:
            prior["_state"] = join(prior["_state"], state)
            prior["artifact_axis"] = LATTICE[prior["_state"]]
            return
        row = {
            "stage": self._stage,
            "via": via,
            "helper": helper,
            "clause_axis": "stopped" if helper in SPEC_DEFINED else "failed",
            "artifact_axis": LATTICE[state],
            "clause": clause,
            "line": getattr(node, "lineno", -1),
            "_state": state,
        }
        self._seen[key] = row
        self.hits.append(row)


def stages(tree: ast.Module) -> list[tuple[str, str, list[str]]]:
    """(letter, handler, declared-output basenames) per Stage entry."""
    out = []
    for c in ast.walk(tree):
        if isinstance(c, ast.Call) and isinstance(c.func, ast.Name) \
                and c.func.id == "Stage" and len(c.args) >= 4:
            letter, handler = c.args[0], c.args[3]
            if not (isinstance(letter, ast.Constant) and isinstance(handler, ast.Name)):
                continue
            decl = []
            if len(c.args) >= 5 and isinstance(c.args[4], ast.Tuple):
                for e in c.args[4].elts:
                    if isinstance(e, ast.Constant) and isinstance(e.value, str):
                        decl.append(e.value.rsplit("/", 1)[-1])
            out.append((letter.value, handler.id, decl))
    return out


def census(writes: set[str], declared_only: bool = False) -> list[dict]:
    tree = ast.parse(DRIVER.read_text(), filename=str(DRIVER))
    rows: list[dict] = []
    for letter, handler, decl in stages(tree):
        c = Census(tree, writes, decl if declared_only else None)
        c.run_stage(letter, handler)
        rows.extend(c.hits)
    return rows


def _key(r: dict) -> tuple:
    return (r["stage"], r["via"], r["helper"], r["clause"], r["line"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    any_rows = census(WRITE_ANY)
    dec_rows = census(WRITE_DECLARED)
    own_rows = census(WRITE_DECLARED, declared_only=True)
    dec_by = {_key(r): r for r in dec_rows}
    own_by = {_key(r): r for r in own_rows}

    if args.json:
        json.dump({"any": any_rows, "file": dec_rows, "own": own_rows},
                  sys.stdout, indent=1)
        return 0

    print(f"halt sites reached from a stage handler: {len(any_rows)}")
    print()
    print("  stage  axis-clause  own-declared   helper        via")
    print("  " + "-" * 74)
    disagree, split, reading = [], [], []
    for r in sorted(any_rows, key=lambda x: (x["stage"], x["line"])):
        d = dec_by.get(_key(r))
        o = own_by.get(_key(r))
        mark = " "
        if o and o["artifact_axis"] == "BOTH":
            split.append(o)
            mark = "*"
        others = {x["artifact_axis"] for x in (d, o) if x}
        if others - {r["artifact_axis"]}:
            reading.append((r, d, o))
            mark = "#"
        if o and o["clause_axis"] == "failed" \
                and o["artifact_axis"] in ("post-write", "BOTH"):
            disagree.append(o)
            mark = "!" if mark == " " else mark
        oa = o["artifact_axis"] if o else "?"
        print(f" {mark}{r['stage']:>4}  {r['clause_axis']:<11}  {oa:<13}"
              f"  {r['helper']:<12}  {r['via']}")

    print()
    print(f"! axes DISAGREE (clause says failed, artifact state says stopped): {len(disagree)}")
    for r in disagree:
        print(f"    {r['stage']}  via {r['via']}  line {r['line']}")
    print(f"* ONE SITE, TWO DISPOSITIONS (loop or branch): {len(split)}")
    for r in split:
        print(f"    {r['stage']}  via {r['via']}  line {r['line']}")
    print(f"# the reading of \"wrote some artifacts\" CHANGES the verdict: {len(reading)}")
    for r, d, o in reading:
        print(f"    {r['stage']}  via {r['via']}  line {r['line']}: "
              f"any={r['artifact_axis']} any-file={d['artifact_axis'] if d else '?'} "
              f"own-declared={o['artifact_axis'] if o else '?'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
