"""DRIVER-LL: the census of proved defs that nothing calls.

A proof about a function no program calls is still a valid proof. That is
exactly why no gate in this repository can catch it: `verify` reports SAFE,
`--strict-verified-core` reports body-faithful, the refute-crux gate reports
that the mutant is caught, and every one of those claims is true of a function
that is never reached. Stage H exists to catch this defect in the RFC-SWARM
target; this file turns it on our own artifacts.

WHY THE COUNT IS DERIVED AND NOT WRITTEN DOWN. The set was first stated from
memory as ten defs across three modules (`fill`, `token`, `liveness`), and
measurement disagreed with that statement in BOTH directions at once, so the
total was right and the membership was wrong:

  * `gate.remedy-for` was missing from it. The statement counted references at
    MODULE granularity, and `gate` has four of them, all to `gate-halts`.
    `remedy-for` has none, which `spine.llmll:42` already says in prose;
  * `liveness.advancing` was in it for the wrong reason. It HAS a caller, at
    `shell.llmll:50`. What makes it unreachable is that no program imports
    `shell`, not that no site names it;
  * `shell.status-line` was missing for the same reason in reverse. It is
    called twice inside `shell.llmll` and reached by nothing.

Two errors cancelling to the right total is the failure mode a remembered
count has and a computed one does not, and it is the same lesson
`test_driver_ll_4b.py:32` and the Rev 13 section 3.6 census each learned
separately. So this file measures two INDEPENDENT properties and asserts the
union rather than asserting a number:

  UNREFERENCED. No site anywhere in the non-crux tree names the def, outside
  its own definition. The remedy is a call site.

  ORPHANED. The def's module is not reachable through `import` from any
  module carrying a `(def-main`. The remedy is an import, and a def in an
  orphaned module is unreachable however many callers it has.

Neither implies the other, which is the whole point of computing both.

BY NAME, WITH A REASON EACH, on proposal section 3.5.1's rule. A bare count
tells a later reader that something is uncalled and not which thing or why,
and the four reasons here have four different remedies on four different
schedules: one sub-phase owes a caller, one sub-phase is parked, one waits on
a capability that does not exist, and two are uncalled on purpose.

THIS FILE IS EXPECTED TO FAIL WHEN 4d OR 4e LANDS. That is its function. 4e
calls `fill.*` and `token.token-during`, 4d calls `oracle.*` and
`shape.probe-rows-conform?`, and either one makes the measured set smaller
than the registered one. Delete the rows that acquired callers; do not widen
the assertion.

4e HAS NOW LANDED and its four rows are deleted rather than widened, taking
the census from twelve to eight. `wave.llmll` is the third program, so `fill`
and `token` left the orphan set with it. FOUR assertions moved, not one, and
that is worth stating because the restart record predicted one: the program
set, the orphan set, the register and the `cfg-llmll` guard all rest on the
same derivation, so a new `def-main` moves all of them together. The guard
moved for a different reason than the other three, recorded at its own site.

NOTHING HERE NEEDS A TOOLCHAIN. It reads source text, so it runs on a machine
with no `llmll` binary, which is the tier `test_driver_ll_4c.py` describes.
"""

from __future__ import annotations

import json
import pathlib
import re

DRIVER_LL = pathlib.Path(__file__).resolve().parents[2] / "tools" / "llmll-driver"

# The non-crux modules. `crux-*` and `twin-*` are deliberate mutants and good
# twins of these files; counting a reference from one would let a mutant keep
# its own subject alive.
MODULES = sorted(
    p.stem for p in DRIVER_LL.glob("*.llmll")
    if not p.stem.startswith(("crux-", "twin-"))
)

# An LLMLL identifier: `?`, `!` and `-` are name characters, so a boundary
# built from `\b` would split `probe-rows-conform?` in three.
_IDENT_TAIL = r"(?![\w?!-])"
_IDENT_HEAD = r"(?<![\w?!-])"


def _src(module: str) -> str:
    return (DRIVER_LL / f"{module}.llmll").read_text()


def _uncommented(module: str) -> str:
    """Source with `;` comment tails removed, string literals respected.

    Every mention of `gate.remedy-for` outside `gate.llmll` today is prose
    explaining that it is deliberately uncalled. Searching raw text would
    find that sentence and conclude it has a caller.
    """
    out = []
    for line in _src(module).splitlines():
        in_str = False
        for i, ch in enumerate(line):
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
            elif ch == ";" and not in_str:
                line = line[:i]
                break
        out.append(line)
    return "\n".join(out)


def _proved_defs(module: str) -> list[str]:
    """The `def` names of a module. `def-shell` is the asserted tier and is
    excluded: it carries no postcondition, so an uncalled one forfeits no
    proof. `\\(def\\s` cannot match `(def-shell` because it requires the
    whitespace."""
    return re.findall(r"\(def\s+([^\s()\[\]]+)", _src(module))


def _local_imports(module: str) -> set[str]:
    return {m for m in re.findall(r"^\s*\(import\s+([a-z][\w-]*)\)",
                                  _src(module), re.M) if m in MODULES}


def _programs() -> set[str]:
    """Modules with an entry point, derived rather than listed. `def-main` is
    what `scripts/build_smoke.sh:647` builds and what makes a module a
    program rather than a library."""
    return {m for m in MODULES if re.search(r"\(def-main" + _IDENT_TAIL, _src(m))}


def _reachable() -> set[str]:
    seen: set[str] = set()
    stack = list(_programs())
    while stack:
        m = stack.pop()
        if m in seen:
            continue
        seen.add(m)
        stack.extend(_local_imports(m))
    return seen


def _reference_count(module: str, name: str) -> int:
    """References to `name` across the non-crux tree, bare or receiver
    qualified, excluding the definition site itself.

    The exclusion matches `def-shell` as well as `def`, so the counter is
    usable on the asserted tier too. Only matching `def` left a `def-shell`
    its own definition as a reference and reported it as called, which is
    how this function's first version scored `cfg-llmll` as read.
    """
    pat = re.compile(_IDENT_HEAD + r"(?:[a-z][\w-]*\.)?" + re.escape(name)
                     + _IDENT_TAIL)
    total = 0
    for m in MODULES:
        text = _uncommented(m)
        if m == module:
            text = re.sub(r"\(def(?:-shell)?\s+" + re.escape(name)
                          + _IDENT_TAIL, "(def __DEFSITE__", text)
        total += len(pat.findall(text))
    return total


def _unreferenced() -> set[str]:
    return {f"{m}.{d}" for m in MODULES for d in _proved_defs(m)
            if _reference_count(m, d) == 0}


def _orphaned() -> set[str]:
    live = _reachable()
    return {f"{m}.{d}" for m in MODULES if m not in live
            for d in _proved_defs(m)}


# ---------------------------------------------------------------------------
# The register. Qualified name -> (remedy class, why it has no caller).
# ---------------------------------------------------------------------------

CALLERLESS: dict[str, tuple[str, str]] = {
    # The four `fill.*` and `token.token-during` rows are DELETED, not widened.
    # `wave.llmll` (sub-phase 4e, stage M) is their first caller: it consumes
    # `fill-accepted` as the per-fill bar, `next-error-budget` as the separated
    # retry budgets, `is-finding` as the finding-versus-protocol-failure
    # classification, and `token-during` twice, once as the guard that admits
    # the agent call and once in every log line's token field.

    # Sub-phase 4d is parked. These five verified SAFE and body-faithful on
    # the first attempt and then had their caller deferred by the pivot to 4e.
    "oracle.probe-established?": (
        "4d-parked",
        "stage H's two-sided bar; crux-probe-polarity-inverted refutes the "
        "half that drops the mutant clause"),
    "oracle.feasibility-established?": (
        "4d-parked",
        "stage H's aggregate over probe rows; no refute crux of its own"),
    "oracle.outcome-as-expected?": (
        "4d-parked",
        "scores a compiler run against the polarity a stage contract "
        "declares; no refute crux of its own"),
    "oracle.matrix-complete?": (
        "4d-parked",
        "stage N's honest denominator; crux-oracle-matrix-drops-unwritable "
        "refutes through BOTH posts, its forward clause being an equality"),
    "shape.probe-rows-conform?": (
        "4d-parked",
        "stage H's pre-write row check; the one def in an otherwise fully "
        "called module, and crux-shape-probe-row-lax is its discriminator"),

    # Waiting on a capability, not on a sub-phase.
    "liveness.advancing": (
        "capability-blocked",
        "HAS a caller at shell.llmll:50 and is unreachable anyway, because no "
        "program imports shell; the real block is FS-STAT-1, since judging "
        "advancement needs an artifact mtime the host cannot yet report"),

    # Uncalled on purpose. These two do not acquire callers on any schedule.
    "gate.remedy-for": (
        "deliberate",
        "spine.llmll:42 states it: the port is AHEAD of the reference, which "
        "emits one remedy for every barrier class, so crux-gate-single-remedy "
        "refutes CURRENT BEHAVIOUR rather than a mutant"),
    "shell.status-line": (
        "deliberate",
        "shell.llmll is the section 15.2 asserted-tier exhibit and is built by "
        "nothing (scripts/build-smoke/smoke.llmll:19 rejected it as the smoke "
        "subject); status-line is called twice inside it and reached by no "
        "program"),
}

# Which of the callerless set have a refute crux naming them in `localized`.
# A proved def with neither a caller nor a discriminating mutant is the
# weakest evidence in this directory, and the point of computing it is that
# the three are named rather than counted.
#
# `fill.is-finding` left this set by acquiring a caller and not by acquiring a
# crux, which is the weaker of the two remedies and is why the row said a
# caller was its only evidence.
UNCRUXED = {
    "oracle.feasibility-established?",
    "oracle.outcome-as-expected?",
    "shell.status-line",
}


# ---------------------------------------------------------------------------
# 1. The two properties, measured separately
# ---------------------------------------------------------------------------

def test_the_programs_are_derived_and_are_the_expected_three():
    """If a fourth `def-main` appears, the reachability base changes under
    every assertion below and they must be re-measured rather than trusted.

    `wave` is the third and it arrived exactly this way: the assertion below
    was written for two, a `def-main` landed, and every other assertion in
    this file moved with it."""
    assert _programs() == {"sequencer", "spine", "wave"}


def test_the_orphaned_modules_are_exactly_the_three():
    """`oracle` is orphaned because sub-phase 4d is parked. `liveness` is
    blocked on FS-STAT-1. `shell` is orphaned by construction.

    `fill` and `token` left this set when `wave.llmll` acquired a `def-main`
    and imported them, which is the remedy an orphan takes: an import from a
    program, not a call site. `wave` itself was briefly a sixth member, in the
    window between its decision layer being written and its state machine
    landing."""
    live = _reachable()
    assert {m for m in MODULES if m not in live} == {
        "liveness", "oracle", "shell"}


def test_no_unreferenced_def_hides_in_a_reachable_module():
    """The two properties are independent, so neither census subsumes the
    other. This names the overlap explicitly: the defs that are unreferenced
    while sitting in a module a program does import."""
    live = _reachable()
    assert {q for q in _unreferenced() if q.split(".", 1)[0] in live} == {
        "gate.remedy-for", "shape.probe-rows-conform?"}


# ---------------------------------------------------------------------------
# 2. The union, by name, against the register
# ---------------------------------------------------------------------------

def test_the_callerless_proved_defs_are_exactly_the_registered_set():
    """The assertion 4d and 4e are each expected to break.

    Equality in both directions on purpose: a shrinking set means a caller
    landed and its row is now stale, a growing set means a new proof was
    written with nothing to call it.
    """
    measured = _unreferenced() | _orphaned()
    assert measured == set(CALLERLESS), (
        f"acquired a caller: {sorted(set(CALLERLESS) - measured)}\n"
        f"newly callerless: {sorted(measured - set(CALLERLESS))}")


def test_every_callerless_def_carries_a_reason():
    """`4e-owes-caller` is gone from the class set, which is the shape a
    discharged remedy leaves: the class disappears with its last row rather
    than staying behind as an empty bucket."""
    assert all(cls and why for cls, why in CALLERLESS.values())
    assert {cls for cls, _ in CALLERLESS.values()} == {
        "4d-parked", "capability-blocked", "deliberate"}


def test_the_register_is_not_vacuous_and_names_real_defs():
    """Guards the census against the failure it exists to catch. A typo in a
    key would make its row unfalsifiable, and a module-level `_proved_defs`
    regression would empty every set and pass silently."""
    declared = {f"{m}.{d}" for m in MODULES for d in _proved_defs(m)}
    assert set(CALLERLESS) <= declared
    assert len(declared) > len(CALLERLESS), \
        "every proved def in the directory is callerless, which means the " \
        "reference counter is broken rather than the port"


# ---------------------------------------------------------------------------
# 3. What the callerless set costs, in evidence
# ---------------------------------------------------------------------------

def test_the_defs_with_neither_a_caller_nor_a_refute_crux_are_the_three():
    """A refute crux is the only evidence an uncalled proof has left. These
    three have neither, so nothing about them would change if their body were
    weakened to a constant."""
    verdicts = json.loads((DRIVER_LL / "EXPECTED_VERDICTS.json").read_text())
    localized = {c["localized"] for c in verdicts["cases"] if "localized" in c}
    assert {q for q in CALLERLESS if q.split(".", 1)[1] not in localized} \
        == UNCRUXED


def test_the_llmll_command_accessor_is_read_nowhere():
    """`cfg-llmll` is the config field beside the callerless set, and it is
    `def-shell`, so no assertion above covers it. 4d widened `Cfg` at the tail
    to carry the compiler command and the stage loop that reads it is the
    parked work; the flag is REQUIRED at parse, so a run supplies a value that
    reaches nothing.

    THE SECOND ASSERTION IS THE ONE THAT NEARLY FAILED SILENTLY.
    `_reference_count` is repo-wide and matches a BARE name as well as a
    qualified one, by design, because a caller can live in another module. So
    any second module defining its own `cfg-llmll` makes this guard read four
    references to a def that still has none, and the guard stops being
    falsifiable in the direction it exists for. `wave.llmll` did exactly that
    and its accessor is named `cfg-compiler` for this reason. Asserting the
    name is defined once is what keeps the collision loud.
    """
    assert _reference_count("sequencer", "cfg-llmll") == 0
    definers = [m for m in MODULES
                if re.search(r"\(def(?:-shell)?\s+cfg-llmll" + _IDENT_TAIL,
                             _src(m))]
    assert definers == ["sequencer"], \
        f"a second module defines cfg-llmll, so the count above is not about " \
        f"sequencer's accessor any more: {definers}"
    assert '(flag-value as "--llmll-cmd")' in _uncommented("sequencer"), \
        "the flag is still parsed, so the accessor is unread rather than gone"
