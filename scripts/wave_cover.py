#!/usr/bin/env python3
"""DRIVER-LL sub-phase 4e acceptance cover: the serial wave, stage M.

Drives the BUILT `wave` binary against the hand-authored fixture tree in
`tools/llmll-driver/fixtures/wave-roots.llmll` and the REAL compiler, and
asserts the decisions of `docs/design/driver-ll-phase4-proposal.md` section 9's
4e row: both retry budgets fire and are separately counted, a hole exhausting
its semantic budget is a finding, and a hole that failed for any other reason
is not.

WHY THIS IS A SECOND COVER RATHER THAN CELLS IN `driver_ll_cover.py`. That file
drives the `sequencer` binary through the stage loop with a stub agent and a
stub `llmll`. The wave is a different program with a different entry point, and
its oracle is the compiler itself: every cell below runs real `checkout`, real
`patch` and real `verify`, because the decisions under test are what those
three commands answer. A stub would be testing the stub.

NO STUB COMPILER, AND THAT IS THE POINT OF CELL W4. Rev 15's F-27 refuted this
proposal's own injection design: contention needs no fault injector, because
the checkout CAS is per-FILE against the brief's `source_hash`, so any brief
outstanding across a successful patch is stale. W4 holds TWO BRIEFS
SIMULTANEOUSLY, one taken by this cover and one by the wave, patches the
cover's, and the wave's is refused. The 4e row makes that cell mandatory rather
than optional, because without it the "both budgets fire" clause is vacuous for
the third time by a third mechanism.

THE STDIN BUDGET IS NOT DATA. The console harness consumes one line per step,
and an under-budgeted run exits 70 with `:status` never consulted. This file
reports 70 as a budget error and not as a decision, the same way
`driver_ll_cover.py` does.

W4 DRIVES STDIN IN LOCKSTEP rather than by sleeping. One line in, one line out,
which is exact: `performStep` prints one captured block per step. The injection
window is the single step between the fresh checkout (issued by `working-step`)
and the patch (issued by `fresh-step`), and the cover finds it by watching for
the `agent token=released` line rather than by counting steps, so an arm added
to the machine moves the window without silently moving the cell.

Usage:
    python3 scripts/wave_cover.py --wave /path/to/wave --llmll /path/to/llmll
    WAVE_BIN=... LLMLL_BIN=... python3 scripts/wave_cover.py
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FIXTURE = REPO / "tools" / "llmll-driver" / "fixtures" / "wave-roots.llmll"
# The stage M prompt template, which is a DECLARED INPUT since the stage M agent
# contract (driver-spec section 8 part 3). `registry.stage-prompt` row 13 names
# this basename and `fan-cfg` resolves it under --prompts-dir; the standalone
# `wave` sub-command takes the resolved path as --prompt.
TEMPLATE = REPO / "experiments" / "rfc-swarm" / "prompts" / "stage-M-fill.md"

# One line per step. A two-hole run with one retry is about 20 steps; 400 is
# generous on purpose, because the failure mode of a tight budget is exit 70,
# which is loud but is not the property under test.
BUDGET = 400

# The stub author. `wasi.proc.run` has no env parameter, so the wave cannot
# inject one; WAVE_STUB_MODE is set on the WAVE process by this cover and
# inherited by the child, which is the same channel `driver_ll_cover.py` uses
# for STUB_MODE and the one proposal section 5 item 2 settles.
#
# THE STUB READS ITS RENDERED PROMPT AND ITS BRIEF, which are two of the four
# declared inputs driver-spec section 8 lets the driver commit to. It read the
# brief through `sys.argv[1]` until the stage M agent contract, when that slot
# became the rendered task statement and the brief moved to a plain file in the
# agent's own directory. The stub records its argv so W1 and W10 can assert what
# the wave handed it.
#
# IT WORKS IN ITS OWN DIRECTORY, which is what the wave now passes as the child
# process's working directory. So `brief.json` and `scratch.llmll` are bare
# names here, exactly as the template tells a real agent they are.
STUB = r'''#!/usr/bin/env python3
import json, os, sys

# THE LAST TWO, NOT THE FIRST TWO, and the campaign's real wrapper is why:
# it reads `--model <MODEL> <PROMPT> <OUT>`, so the two paths are at the END of
# a vector whose head the operator chose. A stub keyed on argv[1] would work
# for the bare two-placeholder vector and break for every real one, which is
# the shape cell W10 exists to drive.
prompt_path, out_path = sys.argv[-2], sys.argv[-1]
with open("argv.json", "w") as fh:
    json.dump(sys.argv[1:], fh)

# The rendered prompt must be READABLE. A wave that stopped substituting hands
# over the literal string `{prompt}`, and this open raises, which is the same
# failure the campaign's real wrapper reports as exit 2.
prompt = open(prompt_path).read()

brief = json.load(open("brief.json"))
goal = brief["postcondition_goal"]
var = "n" if "(+ n 1)" in goal else "m"
mode = os.environ.get("WAVE_STUB_MODE", "good")

if mode == "good":
    body = ({"kind": "op", "op": "+",
             "args": [{"kind": "var", "name": "n"}, {"kind": "lit-int", "value": 1}]}
            if var == "n" else
            {"kind": "op", "op": "+",
             "args": [{"kind": "var", "name": "m"}, {"kind": "var", "name": "m"}]})
elif mode == "wrong":
    # Returns its input. Refuted against both posts, and refused at `patch`.
    body = {"kind": "var", "name": var}
else:
    # `fallback`: satisfies the post and is NOT proved from its own body.
    # `string-length` puts the VC outside Sigma_auto, so the function lands in
    # `body-fallback` and `patch` still answers PatchSuccess.
    add = ({"kind": "app", "fn": "string-length",
            "args": [{"kind": "lit-string", "value": "x"}]}
           if var == "n" else {"kind": "var", "name": "m"})
    body = {"kind": "op", "op": "+",
            "args": [{"kind": "var", "name": var}, add]}

with open(out_path, "w") as fh:
    json.dump(body, fh)
'''

# A third function with NO hole whose body is not proved from itself. Used by
# W7 alone: it is what makes "every hole accepted" and "the tree is proved"
# come apart, which is the gap the per-fill bar cannot see and Q-005 records.
FALLBACK_DEF = '''
(def tag [s: int] -> int
  (pre (>= s 0)
    :source "[W3-DOM] the wave fixture's domain is the non-negative ints")
  (post (>= result 0)
    :source "[W3-NONNEG] non-negative in, non-negative out")
  (+ s (string-length "x")))
'''


# THE WAVE IS NO LONGER A PROGRAM. Program unification job (a2) folded stage M
# into the sequencer's stage loop and deleted `wave.llmll`'s `def-main`, so the
# driver is ONE binary. The same state machine still runs, reached through a
# sub-command: `sequencer wave --tree ... --workdir ...` enters it with the
# stage index -1, meaning "not inside a stage loop", and the run exits on the
# wave's own code exactly as it did as a separate program.
#
# Every cell below is unchanged in what it asserts. That is the point: these
# seven cells are sub-phase 4e's acceptance cover, and the fold had to keep them
# grading rather than retire them. Two more (W8, W9) were added when the wave
# started writing its declared output.
SUBCOMMAND = ["wave"]


class Failure(Exception):
    pass


def want(cond: bool, msg: str) -> None:
    if not cond:
        raise Failure(msg)


class Cell:
    """One cell's scratch tree: a fixture, its emitted .ast.json, a stub."""

    def __init__(self, root: Path, name: str, llmll: Path, *, extra_def: str = ""):
        self.dir = root / name
        self.dir.mkdir(parents=True)
        self.llmll = llmll
        src = FIXTURE.read_text() + extra_def
        (self.dir / "roots.llmll").write_text(src)
        r = subprocess.run([str(llmll), "build", "roots.llmll", "--emit"],
                           cwd=self.dir, capture_output=True, text=True)
        want(r.returncode == 0, f"the fixture did not emit a tree: {r.stdout}{r.stderr}")
        self.tree = self.dir / "tree.ast.json"
        shutil.copy(self.dir / "generated" / "roots" / "roots.ast.json", self.tree)
        self.agent = self.dir / "agent.py"
        self.agent.write_text(STUB)
        self.agent.chmod(0o755)
        # The REAL template, not a stand-in. The wave renders whatever
        # `--prompt` names, so a cell driving a hand-written fixture would grade
        # the port against a file the campaign never uses. This is the same
        # file `registry.stage-prompt` row 13 names.
        self.prompt_tpl = TEMPLATE
        self.agent_args = ["{prompt}", "{out}"]

    def argv(self, **over) -> list[str]:
        """The vector every cell starts from.

        `--workdir` IS ABSOLUTE AND WAS THE RELATIVE STRING `wd`. The wave now
        runs the agent with the agent's own directory as its working directory,
        which is what `delegate-cmd` and the reference's AgentRunner both do and
        what makes the template's `verify scratch.llmll` instruction mean
        anything. A relative workdir would then hand the child a path it cannot
        resolve from inside that directory. `driver_ll_cover.py` has passed an
        absolute workdir since it was written.

        `--agent-arg` CARRIES THE PLACEHOLDERS AND NOTHING APPENDS. The wave
        appended `brief.json` and `body.json` to the operator's arguments until
        the stage M agent contract, so a vector with no `--agent-arg` still
        reached the agent carrying two paths. It no longer does: the operator
        says where the prompt and the output go. W1 still asserts exactly two
        paths reach the agent, which is the assertion that mattered.
        """
        a = {"--tree": "tree.ast.json", "--workdir": str(self.dir / "wd"),
             "--llmll-cmd": str(self.llmll), "--agent-cmd": str(self.agent),
             "--prompt": str(self.prompt_tpl), "--pristine": "roots.llmll",
             "--error-budget": "2", "--protocol-budget": "2"}
        a.update(over)
        flat = [x for k, v in a.items() if v is not None for x in (k, v)]
        for ph in self.agent_args:
            flat += ["--agent-arg", ph]
        return flat

    def env(self, mode: str) -> dict:
        e = dict(os.environ)
        e["WAVE_STUB_MODE"] = mode
        return e

    # -- the compiler, used as this cover's own second actor -----------------

    def cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([str(self.llmll), *args], cwd=self.dir,
                              capture_output=True, text=True)

    def checkout(self, pointer: str) -> str:
        r = self.cli("checkout", "tree.ast.json", pointer)
        want(r.returncode == 0, f"the cover's own checkout failed: {r.stderr}")
        return json.loads(r.stdout)["token"]

    def patch(self, token: str, pointer: str, body: dict) -> str:
        req = self.dir / "cover-req.json"
        req.write_text(json.dumps(
            {"token": token, "patch": [{"op": "replace", "path": pointer,
                                        "value": body}]}))
        r = self.cli("patch", "tree.ast.json", "cover-req.json")
        return json.loads(r.stdout)["result"]

    def bodies(self) -> list[str]:
        d = json.loads(self.tree.read_text())
        return [s["body"]["kind"] for s in d["statements"] if "body" in s]


class Run:
    def __init__(self, rc: int, out: str):
        self.rc, self.out = rc, out

    def line(self, needle: str) -> str:
        hits = [ln for ln in self.out.splitlines() if needle in ln]
        want(len(hits) == 1,
             f"expected exactly one line containing {needle!r}, got {len(hits)}"
             f"\n--- transcript ---\n{self.out}")
        return hits[0]

    def count(self, needle: str) -> int:
        return sum(1 for ln in self.out.splitlines() if needle in ln)


def run(binary: Path, c: Cell, mode: str, **over) -> Run:
    p = subprocess.run([str(binary), *SUBCOMMAND, *c.argv(**over)], cwd=c.dir,
                       input="x\n" * BUDGET, capture_output=True, text=True,
                       env=c.env(mode))
    want(p.returncode != 70,
         f"exit 70: stdin was exhausted before :done? fired, so this cell "
         f"observed a starved run rather than a decision\n{p.stdout}")
    return Run(p.returncode, p.stdout + p.stderr)


def want_rc(r: Run, code: int) -> None:
    want(r.rc == code,
         f"expected exit {code}, got {r.rc}\n--- transcript ---\n{r.out}")


# ---------------------------------------------------------------------------
# The cells
# ---------------------------------------------------------------------------

CELLS = []


def cell(name: str, why: str):
    def deco(fn):
        CELLS.append((name, why, fn))
        return fn
    return deco


@cell("W1", "every hole accepted, the tree filled and the whole-tree seal held")
def w1(binary, c: Cell):
    r = run(binary, c, "good")
    want_rc(r, 0)
    want(r.count("ACCEPTED") == 2, f"expected two accepted holes\n{r.out}")
    want("accepted 2 findings 0 protocol-failures 0" in r.out,
         f"the tally disagrees with the per-hole lines\n{r.out}")
    want("SEALED" in r.line("--strict-verified-core"),
         f"the seal did not hold on a fully and faithfully filled tree\n{r.out}")
    want(c.bodies() == ["op", "op"], f"the tree is not filled: {c.bodies()}")
    # THE TWO-ARGUMENT ASSERTION SURVIVES AND ITS REASON CHANGED. This comment
    # used to read "the agent's whole input is the brief path and an output
    # path; a third argument would be a side channel". The claim was right and
    # the mechanism was wrong: driver-spec section 8 forbids a peer's directory,
    # a peer's output and a worked answer, and an argument COUNT establishes
    # none of the three. The agent still receives exactly two paths, because the
    # cover passes exactly two `--agent-arg` placeholders; what changed is that
    # the first names a RENDERED TASK STATEMENT rather than the raw brief, which
    # section 8 part 3 makes a declared input because the driver declares it.
    argv = json.loads(next(c.dir.glob("wd/h0-a0/argv.json")).read_text())
    want(len(argv) == 2, f"the agent was handed {len(argv)} arguments, not 2: {argv}")
    want(argv[0].endswith("PROMPT.md") and argv[1].endswith("body.json"),
         f"the agent's arguments are not (prompt, out): {argv}")


@cell("W2", "a refused patch spends the ERROR budget and exhausting it is a finding")
def w2(binary, c: Cell):
    r = run(binary, c, "wrong")
    want_rc(r, 1)
    want(r.count("FINDING") == 2, f"expected two findings\n{r.out}")
    want(r.count("PROTOCOL-FAILURE") == 0,
         f"a wrong body is a finding and never a protocol failure\n{r.out}")
    # [S9-SPEND]: two attempts, the error budget stepping 2 -> 1 -> 0 while the
    # protocol budget never moves.
    want("(error-budget 1, protocol-budget 2)" in r.out
         and "(error-budget 0, protocol-budget 2)" in r.out,
         f"the error budget did not step while the protocol budget held\n{r.out}")
    want(c.bodies() == ["hole-named", "hole-named"],
         f"a rejected fill was not reverted: {c.bodies()}")


@cell("W3", "a fill that PATCHES CLEANLY and is not body-faithful is rejected")
def w3(binary, c: Cell):
    # The [S9-FAITHFUL] conjunct doing work that `patch` does not do for us.
    # Measured at v0.14.87: this body answers PatchSuccess and `verify` answers
    # SAFE, and add-one lands in `body-fallback`. Without the third conjunct of
    # fill-accepted the wave would accept it.
    r = run(binary, c, "fallback")
    want_rc(r, 1)
    want("PatchSuccess" in (c.dir / "wd/h0-a0/patch.out").read_text(),
         "this cell is only discriminating if the patch SUCCEEDED; it did not, "
         "so it is testing the same thing as W2")
    want("SAFE" in (c.dir / "wd/h0-a0/verify.out").read_text(),
         "this cell is only discriminating if `verify` answered SAFE")
    want("body-fallback: add-one" in (c.dir / "wd/h0-a0/verify.out").read_text(),
         "the fill was expected to fall back rather than be body-faithful")
    want("did not clear the per-fill bar" in r.out,
         f"the fill was not rejected by the per-fill bar\n{r.out}")
    want(c.bodies()[0] == "hole-named",
         f"an unfaithful fill was left in the tree: {c.bodies()}")


@cell("W4", "TWO BRIEFS OUTSTANDING: contention spends the PROTOCOL budget only")
def w4(binary, c: Cell):
    # The cover takes the second brief FIRST and holds it. Both briefs are then
    # outstanding at one source_hash, which is Rev 15 F-27's construction with
    # no stub, no threads and no second writer.
    cover_token = c.checkout("/statements/1/body")
    double = {"kind": "op", "op": "+",
              "args": [{"kind": "var", "name": "m"}, {"kind": "var", "name": "m"}]}

    p = subprocess.Popen([str(binary), *SUBCOMMAND, *c.argv()], cwd=c.dir,
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, bufsize=1,
                         env=c.env("good"))
    wr, rd = p.stdin, p.stdout
    assert wr is not None and rd is not None
    out: list[str] = []
    injected = False

    def step() -> str | None:
        """One line in, one line out. None once the wave has exited.

        The write is guarded because the loop cannot know the run is over
        until it tries: the wave stops reading at `:done?`, so the last write
        this cover attempts lands on a closed pipe rather than returning a
        short read.
        """
        try:
            wr.write("x\n")
            wr.flush()
        except BrokenPipeError:
            return None
        line = rd.readline()
        if line == "":
            return None
        out.append(line.rstrip("\n"))
        return out[-1]

    try:
        for _ in range(BUDGET):
            line = step()
            if line is None:
                break
            # The wave has just been told to run the agent. The NEXT step takes
            # its fresh checkout; the step after that patches. Inject between.
            if not injected and "agent token=released" in line:
                want(step() is not None,
                     "the wave exited before it took its fresh checkout")
                res = c.patch(cover_token, "/statements/1/body", double)
                want(res == "PatchSuccess",
                     f"the cover's own patch had to land for the wave's brief "
                     f"to go stale; it answered {res}")
                injected = True
    finally:
        try:
            wr.close()
        except BrokenPipeError:
            pass
        p.wait(timeout=120)
    r = Run(p.returncode, "\n".join(out))

    want(injected, f"the injection window never opened\n{r.out}")
    # [S9-SEPARATE]: the error budget is UNTOUCHED at its initial 2 and the
    # protocol budget is the one that stepped.
    want("rejected: contention (error-budget 2, protocol-budget 1)" in r.out,
         f"contention did not leave the error budget alone\n{r.out}")
    # Hole 0 recovers: released, re-briefed and accepted on the next attempt.
    want("hole 0 ACCEPTED add-one" in r.out,
         f"the hole did not recover after contention\n{r.out}")
    # Hole 1 is no longer a hole, so its checkout fails. [S9-NOT-FINDING]: that
    # is a protocol failure and MUST NOT be reported as a finding about a hole
    # an agent could not fill.
    want(r.count("PROTOCOL-FAILURE") == 1,
         f"expected one protocol failure for the vanished hole\n{r.out}")
    want(r.count("FINDING") == 0,
         f"a protocol fault was reported as a finding\n{r.out}")
    want_rc(r, 3)


@cell("W5", "a missing required flag stops before any hole exists")
def w5(binary, c: Cell):
    r = run(binary, c, "good", **{"--agent-cmd": None})
    want_rc(r, 2)
    want("--agent-cmd is required" in r.out, f"the stop names no flag\n{r.out}")
    want(r.count("hole") == 0 or "STOP" in r.out,
         f"a run that cannot start must not report on holes\n{r.out}")


@cell("W6", "a .llmll tree is refused at parse, not eight steps later")
def w6(binary, c: Cell):
    # THIS CELL WAS WRITTEN TO A FALSE CLAIM AND CORRECTED BY RUNNING IT. The
    # module first asserted that a .llmll "reads as zero holes"; it does not,
    # `holes` answers the real list for source too. What actually happened was
    # two protocol failures and exit 3 after both budgets were spent on
    # checkouts that could never succeed. The guard now stops at parse.
    r = run(binary, c, "good", **{"--tree": "roots.llmll"})
    want_rc(r, 2)
    want("--tree must be a .ast.json" in r.out,
         f"the stop does not name the cause\n{r.out}")
    want("PROTOCOL-FAILURE" not in r.out,
         f"the run reached the hole loop before stopping\n{r.out}")


@cell("W7", "every hole accepted and the tree STILL not sealed")
def w7(binary, c: Cell):
    # The residue Q-005 names, made observable. The wave only ever looks at the
    # function it filled, so a tree carrying a function that is not proved from
    # its own body passes every per-fill bar and fails the closing check. Code 5
    # exists for exactly this and for nothing else.
    r = run(binary, c, "good")
    want(r.count("ACCEPTED") == 2, f"both holes should still be accepted\n{r.out}")
    want("accepted 2 findings 0 protocol-failures 0" in r.out,
         f"the per-hole tally should be clean\n{r.out}")
    want("NOT SEALED" in r.line("--strict-verified-core"),
         f"the seal held over a tree carrying a body-fallback function\n{r.out}")
    want_rc(r, 5)


@cell("W8", "the declared output wave.json records one row per hole")
def w8(binary, c: Cell):
    # `12-wave/wave.json` is stage M's FIRST declared output (registry.llmll,
    # stage-out i=13 j=0) and this module did not write it until 2026-09-11, so
    # one of the stage's two declared artifacts did not exist. The clause 2
    # comparator reads `fills` for R5 and `attempts` for R6; an absent file makes
    # both report on nothing whatever the wave actually did.
    r = run(binary, c, "good")
    want_rc(r, 0)
    w = json.loads((c.dir / "wd" / "wave.json").read_text())
    fills = w.get("fills")
    want(isinstance(fills, list) and len(fills) == 2,
         f"expected one row per hole, got {fills}")
    want(all({"hole", "pointer", "status", "attempts"} <= set(f) for f in fills),
         f"a row is missing a field the comparator reads: {fills}")
    want([f["status"] for f in fills] == ["filled", "filled"],
         f"a clean run recorded a status other than filled: {fills}")
    # ONE-BASED, and R6 sums this field across holes. `at-n` counts from 0, so a
    # row carrying 0 here is an off-by-n in the comparator and not a cosmetic
    # difference from the reference.
    want([f["attempts"] for f in fills] == [1, 1],
         f"attempts is not one-based: {fills}")
    want(w.get("whole_tree", {}).get("sealed") is True,
         f"the seal verdict did not reach the record: {w.get('whole_tree')}")


@cell("W9", "a finding reaches wave.json as a row, with its budget and its cause")
def w9(binary, c: Cell):
    # W8 alone would pass with a status field hardcoded to "filled". This cell
    # is what makes the status discriminating, and it is also where the ONE
    # divergence from the reference's vocabulary is observed: `is-finding`
    # [S9-FINDING] classifies an exhausted ERROR budget, so the port writes
    # `finding` where the reference would, and `protocol-failure` where the
    # reference writes `checkout-failed`.
    r = run(binary, c, "wrong")
    want_rc(r, 1)
    fills = json.loads((c.dir / "wd" / "wave.json").read_text())["fills"]
    want([f["status"] for f in fills] == ["finding", "finding"],
         f"a rejected hole was not recorded as a finding: {fills}")
    want(all(f["attempts"] == 2 for f in fills),
         f"the row does not carry the attempts the budget actually allowed: {fills}")
    want(all(f.get("last_error") for f in fills),
         f"a finding row carries no cause: {fills}")
    want(json.loads((c.dir / "wd" / "wave.json").read_text())
         ["whole_tree"]["sealed"] is False,
         "a tree with holes left in it must not record as sealed")


# ---------------------------------------------------------------------------
# The stage M agent contract: the three cells no gate had
# ---------------------------------------------------------------------------
#
# THREE GATES AND THE TEMPLATED PATH WAS OUTSIDE ALL THREE. No cell passed
# `--agent-arg`, so the untemplated case was the only one this cover exercised;
# `driver_ll_cover.py` stopped selecting stage M at the (a2) fold; and the
# 2026-09-11 clause 2 run never reached stage M because stage M was stubbed. The
# defect that survived all three is measured in
# `docs/design/driver-ll-stage-m-agent-contract-proposal.md` section 1.


@cell("W10", "the argument vector is SUBSTITUTED per argument and the model pin "
             "survives")
def w10(binary, c: Cell):
    # THE CELL SECTION 4.5 OWES. It fails if the substitution is lost: without
    # it the agent's third argument is the literal string `{prompt}`, the stub's
    # `open(prompt_path)` raises, no body.json is written, and both budgets go.
    c.agent_args = ["--model", "stub-opus", "{prompt}", "{out}"]
    r = run(binary, c, "good")
    want_rc(r, 0)
    argv = json.loads(next(c.dir.glob("wd/h0-a0/argv.json")).read_text())
    want(len(argv) == 4, f"the agent was handed {len(argv)} arguments, not 4: {argv}")
    # THE PIN, and it is not incidental. The clause 2 pre-registration section
    # 6.2 checks the model by reading the argument vector the run recorded, so
    # an invocation that dropped `--model` would break that check for eleven of
    # a campaign's agent sessions.
    want(argv[0] == "--model" and argv[1] == "stub-opus",
         f"an argument carrying no placeholder was not passed through: {argv}")
    want("{prompt}" not in argv and "{out}" not in argv,
         f"a placeholder reached the agent unsubstituted: {argv}")
    want(argv[2].endswith("PROMPT.md") and argv[3].endswith("body.json"),
         f"the substituted paths are not (prompt, out): {argv}")
    prompt = (c.dir / "wd" / "h0-a0" / "PROMPT.md").read_text()
    want("{{" not in prompt,
         "the rendered prompt still carries a placeholder; the wave is supposed "
         "to halt on that rather than hand it over")
    # DISCRIMINATING, not a presence check: the rendered values have to be THIS
    # hole's. A renderer keyed on the wrong hole passes every check above.
    want("add-one" in prompt, f"the prompt does not name hole 0's function")
    want(c.llmll.name in prompt or str(c.llmll) in prompt,
         "the prompt does not carry the compiler command the agent self-checks "
         "with; {{llmll}} was not substituted")
    want("postcondition_goal" in prompt,
         "the prompt does not carry the checkout brief; {{brief}} was not "
         "substituted")


@cell("W11", "attempt n+1 renders attempt n's compiler output, and attempt 1 "
             "says so")
def w11(binary, c: Cell):
    # THE ERROR CHANNEL, and it is not cosmetic. driver-spec section 9 requires
    # two separately counted retry budgets and makes only an exhausted error
    # budget a finding. The port cleared the token and the body and carried only
    # the budgets, so attempt n+1 received BYTE-IDENTICAL input to attempt n:
    # the error budget sampled agent nondeterminism where the reference's
    # measures repair. `fill.next-error-budget` was always correct; what was
    # missing is the input that gives the budget meaning.
    r = run(binary, c, "wrong")
    want_rc(r, 1)
    first = (c.dir / "wd" / "h0-a0" / "PROMPT.md").read_text()
    second = (c.dir / "wd" / "h0-a1" / "PROMPT.md").read_text()
    want("(first attempt)" in first,
         "attempt 1 does not render the reference's literal, so its prompt "
         "leaves a heading with nothing under it")
    want("(first attempt)" not in second,
         "attempt 2 still says it is the first attempt; the errors slot was "
         "cleared rather than carried")
    # The two prompts must actually DIFFER, which is the whole claim.
    want(first != second,
         "attempt 2 received byte-identical input to attempt 1")
    # And the difference must be the compiler's output rather than any change.
    want("PatchAuthError" in second or "refuted" in second or "verify" in second
         or "SAFE" in second or "body-fallback" in second,
         f"attempt 2's prompt carries no compiler transcript:\n{second[-1200:]}")


@cell("W12", "the agent's directory holds the PRISTINE subject and the language "
             "reference")
def w12(binary, c: Cell):
    # driver-spec section 8 part 4: where the agent needs a copy of the subject
    # to check its own work, the copy MUST be the original, unmodified subject.
    # `FS-COPY-1` shipped `wasi.fs.copy` citing that clause, and sub-phase 4e
    # then used the builtin for its per-attempt backup and never for the agent's
    # copy, so the mechanism existed and the clause it was built for was unmet.
    refdir = c.dir / "refdir"
    (refdir / "docs").mkdir(parents=True)
    (refdir / "LLMLL.md").write_text("# stand-in language reference\n")
    (refdir / "docs" / "llmll-ast.schema.json").write_text('{"stand-in": true}\n')
    r = run(binary, c, "good", **{"--reference-dir": str(refdir)})
    want_rc(r, 0)
    d = c.dir / "wd" / "h0-a0"
    scratch = d / "scratch.llmll"
    want(scratch.exists(), "the agent got no pristine copy to self-check against")
    # PRISTINE MEANS THE AUTHORED ROOTS AND NOT THE TREE. This is the assertion
    # that discriminates: point the copy at `--tree` instead and hole 1's
    # directory holds hole 0's ACCEPTED FILL, which is a peer's output and is
    # what section 8 forbids by name.
    want(scratch.read_text() == (c.dir / "roots.llmll").read_text(),
         "the scratch copy is not byte-identical to the authored roots")
    want("?body-" in scratch.read_text(),
         "the scratch copy carries no named holes, so it is a filled tree "
         "rather than the pristine subject")
    late = c.dir / "wd" / "h1-a0" / "scratch.llmll"
    want(late.exists() and late.read_text() == (c.dir / "roots.llmll").read_text(),
         "the SECOND hole's copy is not pristine; it carries hole 0's fill, "
         "which is a peer's output (driver-spec sec 8)")
    # The language reference, which is `_provision_reference`'s pair. The tool
    # manual and not the answer: neither file says anything about the subject.
    want((d / "LLMLL.md").exists(),
         "the agent was asked to write LLMLL with no language reference")
    want((d / "llmll-ast.schema.json").exists(),
         "the schema the template calls the authority on node shapes is absent")
    # The schema loses its directory on the way in, as the reference's
    # `wd / src.name` does, so the template's bare file name resolves.
    want(not (d / "docs").exists(),
         "the schema arrived under docs/ and the template names it bare")


@cell("W13", "a prompt template that cannot be read stops the wave at code 6")
def w13(binary, c: Cell):
    # THE WITNESS FOR A GUARD THAT WOULD OTHERWISE BE DEAD CODE. `fan-join`
    # gained an arm for code 6 and `test_driver_ll_a2.py` asserts its
    # disposition statically, but a halt no cell reaches is a halt nobody has
    # seen fire. Every other delegated stage halts on its template read
    # (`tmpl-step`, Absent); stage M reaches its template through the wave, and
    # this is where that condition is exercised.
    r = run(binary, c, "good", **{"--prompt": str(c.dir / "not-a-template.md")})
    want_rc(r, 6)
    want("STOP" in r.out and "not readable" in r.out,
         f"the stop does not name the cause\n{r.out}")
    # BEFORE ANY HOLE, which is the point of reading at boot rather than per
    # attempt: a --prompts-dir fault is a setup error and must not surface nine
    # steps into a run that has already spent a checkout.
    want("ACCEPTED" not in r.out and "briefing" not in r.out,
         f"the wave reached the hole loop before noticing its template\n{r.out}")


@cell("W14", "a rendered prompt that kept a placeholder stops at code 7 rather "
             "than reaching the agent")
def w14(binary, c: Cell):
    # The reference's `ctx.prompt` ends with `require(not left, ...)`, so an
    # unfilled placeholder is a stage failure there. A port without this check
    # hands the agent the literal string `{{scope}}` and the run looks healthy
    # until someone reads a prompt. THE TEMPLATE IS THE REAL ONE PLUS ONE LINE,
    # so this cell measures the port's renderer against a template edit rather
    # than against a hand-written stand-in.
    edited = c.dir / "edited-template.md"
    edited.write_text(TEMPLATE.read_text() + "\n## A section added later\n\n{{scope}}\n")
    r = run(binary, c, "good", **{"--prompt": str(edited)})
    want_rc(r, 7)
    want("{{placeholder}}" in r.out or "placeholder" in r.out,
         f"the stop does not name the cause\n{r.out}")
    want(not list(c.dir.glob("wd/h0-a0/argv.json")),
         "the agent ran on a prompt the wave could not finish rendering")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--wave", default=os.environ.get("WAVE_BIN", ""))
    ap.add_argument("--llmll", default=os.environ.get("LLMLL_BIN", "llmll"))
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    if not a.wave:
        print("ERROR: pass --wave or set WAVE_BIN to the built DRIVER binary "
              "(llmll build tools/llmll-driver/sequencer.llmll). The wave is a "
              "library since program unification job (a2); this cover drives it "
              "through the `wave` sub-command.", file=sys.stderr)
        return 2
    binary = Path(a.wave).resolve()
    llmll = Path(shutil.which(a.llmll) or a.llmll).resolve()
    for p, what in ((binary, "wave binary"), (llmll, "llmll binary")):
        if not p.exists():
            print(f"ERROR: {what} {p} does not exist", file=sys.stderr)
            return 2
    if not FIXTURE.exists():
        print(f"ERROR: the fixture {FIXTURE} does not exist", file=sys.stderr)
        return 2

    root = Path(tempfile.mkdtemp(prefix="driver-ll-4e-"))
    npass = nfail = 0
    try:
        for name, why, fn in CELLS:
            try:
                c = Cell(root, name, llmll,
                         extra_def=FALLBACK_DEF if name == "W7" else "")
                fn(binary, c)
            except Failure as e:
                nfail += 1
                print(f"  FAIL {name:4s} {why}\n        {e}")
            else:
                npass += 1
                print(f"  ok   {name:4s} {why}")
    finally:
        if not a.keep:
            shutil.rmtree(root, ignore_errors=True)
        else:
            print(f"  workdirs kept under {root}")

    print(f"DRIVER-LL 4e wave cover: {npass} passed, {nfail} failed")
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
