"""DRIVER-LL sub-phase 4a: the checks that need no toolchain.

`scripts/driver_ll_cover.py` is the acceptance cover and it needs a BUILT
`sequencer` binary, so it runs in `scripts/build_smoke.sh` where the toolchain
exists. Three things about it can be checked without building anything, and all
three are places where the port could drift silently:

  * the cover's scenario names are the Python-side test names, so the two
    covers stay two harnesses asking the same question rather than two
    questions (proposal section 2.3 derives the cover once and both sides
    instantiate it);
  * the sequencer carries both of the section 7 disclosures 4a owes, so a
    header rewrite that drops one is loud;
  * the LLMLL stage registry agrees with the Python one, field by field. That
    one is the real drift surface: `registry.llmll` is a hand-written table and
    `STAGES` is the thing it is a port of, and nothing but this test relates
    them.

The fourth test runs the cover itself and SKIPS unless DRIVER_LL_BIN points at
a built binary. It is here so a developer who has one gets the cover from
`pytest` too; CI gets it from the build gate.
"""
import importlib.util
import os
import pathlib
import re
import subprocess
import sys

import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]
COVER = REPO / "scripts" / "driver_ll_cover.py"
RIG = REPO / "scripts" / "tests" / "test_rfc_pipeline_integration.py"
SEQUENCER = REPO / "tools" / "llmll-driver" / "sequencer.llmll"
REGISTRY = REPO / "tools" / "llmll-driver" / "registry.llmll"
DRIVER = REPO / "scripts" / "rfc_to_implementation.py"

_spec = importlib.util.spec_from_file_location("rfc_driver_4a", DRIVER)
assert _spec and _spec.loader
drv = importlib.util.module_from_spec(_spec)
sys.modules["rfc_driver_4a"] = drv
_spec.loader.exec_module(drv)


def _mirrored_names() -> list[str]:
    """The Python-side test each cover scenario claims to mirror."""
    src = COVER.read_text()
    return re.findall(r'@scenario\("[^"]+",\s*"([^"]+)"\)', src)


def test_every_cover_scenario_mirrors_a_test_that_exists():
    """The mirror risk, and the cheapest possible mitigation for it.

    The LLMLL driver cannot be substituted into the rig: 4a lands no stage
    bodies, so `--agent-cmd` and `--llmll-cmd` reach nothing. The two covers
    are therefore two programs asserting the same decisions, and a divergence
    between them would be invisible. Requiring the names to match makes a
    scenario that has quietly stopped corresponding to anything fail here.
    """
    rig_tests = set(re.findall(r"^def (test_\w+)", RIG.read_text(), re.M))
    mirrored = _mirrored_names()
    assert len(mirrored) == 14, (
        "the cover is eleven transition cells plus three corrupt-manifest "
        f"shapes; found {len(mirrored)}")
    assert len(set(mirrored)) == 14, "two scenarios claim the same mirror"
    missing = [n for n in mirrored if n not in rig_tests]
    assert not missing, (
        f"the cover mirrors tests that do not exist in {RIG.name}: {missing}")


def test_the_sequencer_carries_both_section_7_disclosures():
    """Proposal section 9's 4a row: "section 7's two 4a statements are
    written". Both are in the module header, on the pattern spine.llmll:71-80
    set for stage E, and both are anchored so this check cannot pass on a
    paraphrase that dropped one."""
    src = SEQUENCER.read_text()
    for anchor in ("[DISCLOSURE skip.may-skip]", "[DISCLOSURE stage.record-outcome]"):
        assert anchor in src, f"section 7 disclosure {anchor} is missing"
    # The skip.may-skip statement is the one that GREW: proposal Rev 7 lists
    # two shell-side decisions and the port owes four, the extra two coming
    # from wasi.fs.sha256 collapsing presence and digest into one command.
    head = src.split("(module sequencer")[0]
    assert "wasi.fs.sha256" in head, (
        "the may-skip disclosure must name the command the two booleans are "
        "derived from")
    assert "4a-injector" in head or "injector" in head, (
        "the record-outcome disclosure must name what chooses the constructor "
        "at 4a")


def _llmll_table(fn: str) -> dict[int, list[str]]:
    """Parse one if-chain out of registry.llmll into {index: [strings]}."""
    src = REGISTRY.read_text()
    block = src.split(f"(def-shell {fn} ")[1].split("\n(def-shell ")[0]
    parts = re.split(r"\(if \(= i (\d+)\)", block)
    return {int(i): re.findall(r'"([^"]*)"', body)
            for i, body in zip(parts[1::2], parts[2::2])}


def test_the_llmll_registry_agrees_with_the_python_registry():
    """Field by field over all sixteen stages.

    The port's registry is a hand-written if-chain and the reference's is a
    list of dataclasses; nothing in either language relates them. A stage
    renamed, re-kinded, or given another declared output on the Python side
    would leave the port deciding over a table that no longer describes the
    pipeline, and every cover scenario would still pass, because the cover
    reads the SAME table it is checking.
    """
    keys = _llmll_table("stage-key")
    kinds = _llmll_table("stage-kind")
    names = _llmll_table("stage-name")
    outs = _llmll_table("stage-out")
    counts = dict(re.findall(r"\(= i (\d+)\) (\d+)",
                             REGISTRY.read_text().split("(def-shell stage-out-count ")[1]
                             .split("\n(def-shell ")[0]))

    assert len(drv.STAGES) == 16, "the reference registry moved; so must the port"
    for i, st in enumerate(drv.STAGES):
        assert keys[i][0] == st.key, f"stage {i}: key"
        assert kinds[i][0] == st.kind, f"stage {st.key}: kind"
        assert names[i][0] == st.name, f"stage {st.key}: name"
        assert outs[i][:len(st.outputs)] == list(st.outputs), \
            f"stage {st.key}: declared outputs"
        want = len(st.outputs)
        got = int(counts.get(str(i), 1))
        assert got == want, f"stage {st.key}: stage-out-count says {got}, not {want}"


@pytest.mark.skipif(not os.environ.get("DRIVER_LL_BIN"),
                    reason="set DRIVER_LL_BIN to a built sequencer binary; "
                           "the build gate runs this cover in CI")
def test_the_4a_cover_passes_against_a_built_sequencer():
    p = subprocess.run([sys.executable, str(COVER)], capture_output=True, text=True)
    assert p.returncode == 0, p.stdout + p.stderr
