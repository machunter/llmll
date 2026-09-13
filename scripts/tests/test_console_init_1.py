"""CONSOLE-INIT-1: no tracked program declares a non-unit state with no `:init`.

A source-level census, and it exists because CI sweeps no corpus with `llmll
check`. `scripts/check-examples.sh` runs in no job (open-work R-1), and
`scripts/build_smoke.sh` reaches exactly one example, `examples/replay-demo`.
A regression there would be caught, because `llmll build` gates on the type
checker. A regression in `examples/proof_required_test`, or in any example added
later, would be caught by nothing.

The compiler check is the real enforcement. `TypeCheck.checkInitRequired`
rejects a `def-main` that omits `:init` unless the step declares a `unit` state.
This test is the corpus half of the same rule, and it needs no toolchain: it
reads the tracked sources and resolves each `:step` to its declaration.

SCOPE MATCHES THE COMPILER'S. `:mode cli` is excluded here for the reason it is
excluded there: `emitMainBody` ModeCli emits `print (step args)` and binds no
`state0`, so that harness has no state to get wrong.

A `:step` written as an inline `fn` is read in place. A `:step` naming a
function is resolved to its `def`/`def-shell` in the same file. A name this
module cannot resolve is REPORTED, never skipped silently: an unresolvable step
is the one case where this census could go quiet while the corpus drifts.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

# `(def-main` through the matching paren, found by balance rather than by regex,
# because the form spans lines and nests.
_DEF_MAIN = "(def-main"


def _tracked_llmll_sources() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "-z", "*.llmll"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return [REPO_ROOT / p for p in out.split("\0") if p]


def _strip_comments(src: str) -> str:
    """Blank out `;;` comments, keeping offsets so slices stay aligned."""
    out = []
    in_string = False
    i = 0
    while i < len(src):
        ch = src[i]
        if in_string:
            if ch == "\\" and i + 1 < len(src):
                out.append(src[i : i + 2])
                i += 2
                continue
            if ch == '"':
                in_string = False
            out.append(ch)
        elif ch == '"':
            in_string = True
            out.append(ch)
        elif ch == ";":
            j = src.find("\n", i)
            j = len(src) if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def _balanced_forms(src: str, head: str) -> list[str]:
    """Every `head ...)` form in `src`, sliced on paren balance."""
    forms = []
    i = 0
    while True:
        i = src.find(head, i)
        if i < 0:
            return forms
        depth = 0
        j = i
        while j < len(src):
            if src[j] == "(":
                depth += 1
            elif src[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        forms.append(src[i : j + 1])
        i = j + 1


def _state_param_type(param_list: str) -> str | None:
    """The type of the FIRST `name: type` parameter in a `[...]` binder list."""
    m = re.search(r"\[\s*[\w?!*<>=/+-]+\s*:\s*([^\]]+?)(?:\s+[\w?!*<>=/+-]+\s*:|\s*\])",
                  param_list, re.S)
    if not m:
        return None
    return " ".join(m.group(1).split())


def _resolve_step_state_type(src: str, step: str) -> tuple[str | None, str]:
    """Return (state type, how it was found) for a `:step` token or inline fn."""
    if step.startswith("(fn"):
        return _state_param_type(step), "inline fn"
    decl = re.search(
        r"\((?:def-shell|def)\s+" + re.escape(step) + r"(?![\w?!*<>=/+-])(\s*\[[^\]]*\])",
        src,
        re.S,
    )
    if not decl:
        return None, f"unresolved name {step!r}"
    return _state_param_type(decl.group(1)), f"declaration of {step}"


def _def_main_facts(path: Path):
    """Yield (mode, has_init, step_text) for each def-main in `path`."""
    src = _strip_comments(path.read_text(encoding="utf-8"))
    for form in _balanced_forms(src, _DEF_MAIN):
        mode_m = re.search(r":mode\s+([\w-]+)", form)
        mode = mode_m.group(1) if mode_m else "?"
        has_init = re.search(r":init(?![\w?!-])", form) is not None
        step_m = re.search(r":step\s+(\(fn\b|[^\s)]+)", form)
        if step_m and step_m.group(1) == "(fn":
            step = _balanced_forms(form[step_m.start(1):], "(fn")[0]
        else:
            step = step_m.group(1) if step_m else ""
        yield src, mode, has_init, step


def test_census_finds_the_def_main_population():
    """Guard the census itself: a parser that finds nothing passes vacuously."""
    total = sum(len(list(_def_main_facts(p))) for p in _tracked_llmll_sources())
    assert total >= 50, (
        f"the def-main census found only {total} forms; the tracked corpus had 53 "
        "when CONSOLE-INIT-1 shipped. A sharp drop means this file's parser broke, "
        "not that the corpus shrank."
    )


def test_no_init_implies_a_unit_state():
    """CONSOLE-INIT-1, over every tracked .llmll source."""
    offenders = []
    unresolved = []
    for path in _tracked_llmll_sources():
        rel = path.relative_to(REPO_ROOT)
        for src, mode, has_init, step in _def_main_facts(path):
            if has_init or mode == "cli":
                continue
            state_ty, how = _resolve_step_state_type(src, step)
            if state_ty is None:
                unresolved.append(f"{rel}: :step {step!r} ({how})")
            elif state_ty != "unit":
                offenders.append(
                    f"{rel}: :mode {mode} has no :init and its step declares "
                    f"state: {state_ty} (from the {how})"
                )

    assert not unresolved, (
        "this census could not resolve a :step to a declaration, so it cannot "
        "speak for these programs. Extend the resolver rather than deleting the "
        "case:\n  " + "\n  ".join(unresolved)
    )
    assert not offenders, (
        "CONSOLE-INIT-1: a def-main with no :init must declare a unit state, or "
        "the harness starts the program on () with a type it did not declare. "
        "Add :init, or declare the state parameter as unit:\n  "
        + "\n  ".join(offenders)
    )


@pytest.mark.parametrize(
    "rel",
    [
        "examples/replay-demo/replay-demo.llmll",
        "examples/proof_required_test/proof_required_test.llmll",
    ],
)
def test_the_two_migrated_examples_stay_migrated(rel):
    """The named migration, pinned. These are the corpus's only no-:init forms.

    They are pinned by name as well as by the sweep above, because they are the
    two programs the rule was measured against, and `examples/replay-demo` is
    the one `scripts/build_smoke.sh` builds and runs.
    """
    path = REPO_ROOT / rel
    facts = list(_def_main_facts(path))
    assert facts, f"{rel} has no def-main"
    for src, _mode, has_init, step in facts:
        assert not has_init, f"{rel} acquired an :init; the migration was to unit state"
        state_ty, how = _resolve_step_state_type(src, step)
        assert state_ty == "unit", f"{rel}: state is {state_ty!r} (from the {how})"
