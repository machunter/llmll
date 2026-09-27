"""The dry-run stub fills a hole with a placeholder of the hole's type.

Before, every stub was a string literal, so a dry run on any non-string hole
failed the type check at patch and exercised nothing past it.
"""

import os
import shutil
import tempfile
from pathlib import Path

import pytest

from llmll_orchestra.__main__ import main
from llmll_orchestra.agent import (
    AgentError,
    DryRunAgent,
    OpenAIAgent,
    _api_error,
    stub_value,
)
from llmll_orchestra.compiler import Compiler, HoleEntry
from llmll_orchestra.orchestrator import Orchestrator

TYPE_DEFS = [
    {"name": "Decision", "kind": "sum",
     "constructors": [{"name": "Reuse"}, {"name": "Fresh"}, {"name": "Deny"}]},
    {"name": "Wrap", "kind": "sum", "constructors": [{"name": "Wrap", "payload": "int"}]},
    {"name": "Port", "kind": "dependent", "base_type": "int"},
    {"name": "Loop", "kind": "alias", "base_type": "Loop"},
]


@pytest.mark.parametrize("type_str, expected", [
    ("int", {"kind": "lit-int", "value": 0}),
    ("float", {"kind": "lit-float", "value": 0.0}),
    ("bool", {"kind": "lit-bool", "value": False}),
    ("unit", {"kind": "lit-unit"}),
    ("string", {"kind": "lit-string", "value": "<s>"}),
    ("int (constrained)", {"kind": "lit-int", "value": 0}),
    ("list[int]", {"kind": "lit-list", "items": []}),
    ("map[int,string]", {"kind": "app", "fn": "map-empty", "args": []}),
    ("bytes[4]", {"kind": "app", "fn": "bytes-zero", "args": []}),
    ("Result[int,string]", {"kind": "app", "fn": "ok", "args": [{"kind": "lit-int", "value": 0}]}),
    ("Result[list[int], string]",
     {"kind": "app", "fn": "ok", "args": [{"kind": "lit-list", "items": []}]}),
    ("(int, bool)", {"kind": "pair", "fst": {"kind": "lit-int", "value": 0},
                     "snd": {"kind": "lit-bool", "value": False}}),
    ("Decision", {"kind": "var", "name": "Reuse"}),
    ("Wrap", {"kind": "app", "fn": "Wrap", "args": [{"kind": "lit-int", "value": 0}]}),
    ("Port", {"kind": "lit-int", "value": 0}),
])
def test_stub_value_per_type(type_str, expected):
    assert stub_value(type_str, TYPE_DEFS, "<s>") == expected


@pytest.mark.parametrize("type_str", [None, "", "Unknown", "Loop", "fn[1 args] -> int"])
def test_unbuildable_types_fall_back_to_a_string(type_str):
    assert stub_value(type_str, TYPE_DEFS, "<s>") == {"kind": "lit-string", "value": "<s>"}


def _hole(inferred_type=None):
    return HoleEntry(pointer="/statements/0/body", kind="delegate", status="agent-task",
                     agent="@a", message="m", module_path="m", inferred_type=inferred_type)


def test_fill_hole_prefers_the_brief_return_type():
    resp = DryRunAgent().fill_hole(
        _hole("string"),
        {"expected_return_type": "Decision", "type_definitions": TYPE_DEFS})
    assert resp.patch_ops[0]["value"] == {"kind": "var", "name": "Reuse"}


def test_fill_hole_uses_the_inferred_type_without_a_brief():
    resp = DryRunAgent().fill_hole(_hole("int"), None)
    assert resp.patch_ops[0]["value"] == {"kind": "lit-int", "value": 0}


def test_openai_needs_an_explicit_model(capsys):
    assert main(["x.ast.json", "--provider", "openai"]) == 1
    assert "--model" in capsys.readouterr().err
    with pytest.raises(AgentError) as e:
        OpenAIAgent(api_key="unused").call_llm("s", "u")
    assert e.value.fatal


class _Status401(Exception):
    status_code = 401


def test_401_names_the_key_variable():
    err = _api_error(_Status401("Error code: 401"), "OPENAI_API_KEY")
    assert err.fatal and "OPENAI_API_KEY" in str(err)


@pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll")
def test_dry_run_patches_every_typed_hole_through_the_real_compiler():
    fixture = Path(__file__).parent / "data" / "typed_holes.ast.json"
    work = Path(tempfile.mkdtemp()) / "typed_holes.ast.json"
    shutil.copy(fixture, work)
    compiler = Compiler(binary=os.environ["LLMLL_BIN"])
    report = Orchestrator(compiler=compiler, agent=DryRunAgent(), max_retries=1).run(str(work))
    failed = {r.pointer: r.error for r in report.results if not r.success}
    assert failed == {}
    assert report.filled == 7
