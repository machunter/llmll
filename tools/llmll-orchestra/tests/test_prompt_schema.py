"""Every JSON-AST node the fill-agent prompt shows is one the schema accepts.

The prompt is the only JSON-AST reference a fill agent gets besides the
compiler spec, and it had drifted: `lambda` params with a `type` key (the reader
ignores it, so the parameter goes untyped), `pair-type` with
`first_type`/`second_type` (the reader wants `fst`/`snd`), `fn-type` with
`param_types`, and advice to use `def-logic`, removed in v0.12.1. Nothing read
the examples, so nothing failed. This file reads them.

Placeholders (`<expr>`, `<type>`, `<pat>`, a bare `v` in `[v]`) are replaced
by a minimal valid node before each example is validated against the
definition its `kind` selects.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from llmll_orchestra.agent import SYSTEM_PROMPT

jsonschema = pytest.importorskip("jsonschema")

SCHEMA_PATH = Path(__file__).resolve().parents[3] / "docs" / "llmll-ast.schema.json"
SCHEMA = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
DEFS = SCHEMA["$defs"]

_EXPR = '{"kind": "var", "name": "x"}'
_PLACEHOLDERS = [
    (", ...]", "]"),
    ("<expression-node>", _EXPR),
    ("<pair-expr>", _EXPR),
    ("<expr>", _EXPR),
    ("<value>", _EXPR),
    ("<pat>", '{"kind": "wildcard"}'),
    ("<type>", '{"kind": "primitive", "name": "int"}'),
    ("[v]", '[{"kind": "var", "name": "v"}]'),
    ("[e]", '[{"kind": "var", "name": "e"}]'),
]


def _balanced_objects(text: str) -> list[str]:
    """Every top-level `{"kind": ...}` object literal in the text."""
    out, i = [], 0
    while True:
        i = text.find('{"kind"', i)
        if i < 0:
            return out
        depth = 0
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    out.append(text[i:j + 1])
                    i = j + 1
                    break
        else:
            return out


def _examples() -> list[str]:
    found = _balanced_objects(SYSTEM_PROMPT)
    assert len(found) >= 15, f"found only {len(found)} examples; the extractor broke"
    return found


def _definition_for(kind: str) -> str:
    for union in ("Pattern", "Type", "Expr"):
        if kind in DEFS[union]["properties"]["kind"]["enum"]:
            return union
    raise AssertionError(f"the prompt shows kind {kind!r}, which no schema union lists")


@pytest.mark.parametrize("example", _examples())
def test_prompt_example_validates(example):
    text = example
    for old, new in _PLACEHOLDERS:
        text = text.replace(old, new)
    node = json.loads(text)
    union = _definition_for(node["kind"])
    v = jsonschema.Draft202012Validator({"$ref": f"#/$defs/{union}", "$defs": DEFS})
    errors = [e.message for e in v.iter_errors(node)]
    assert errors == [], f"{example} fails {union}: {errors}"


def test_prompt_names_no_removed_kind():
    assert "use `def-logic`" not in SYSTEM_PROMPT
    assert '"first_type"' not in SYSTEM_PROMPT and '"param_types"' not in SYSTEM_PROMPT
