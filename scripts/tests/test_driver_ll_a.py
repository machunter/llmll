"""DRIVER-LL stage A: the checks that need no built sequencer.

Stage A fetches the RFC as verbatim bytes over `wasi.http.get` (v0.21.0, the
row that lifted the STOP this stage carried since v0.14.83), writes it under
the URL's basename, and pins its SHA-256 and newline count in
`00-source/PROVENANCE.json`. The acceptance cover (`scripts/driver_ll_cover.py`,
cells A1 to A6) fetches from a listener the cover starts on 127.0.0.1 and
needs a toolchain. Everything below is static.

Five things about the port are settleable statically:

  * `stage-ported?` claims index 0, so the 4a stub write for A is retired;
  * the sequencer calls `wasi.http.get` exactly once, URL first, from the
    fetch command, and nowhere else;
  * the pin carries the four keys the reference's dict carries, by AST;
  * `--rfc-url` is parsed and required, `--amend-url` is parsed repeatably,
    and the cover passes `--rfc-url` on every run;
  * the file name is the reference's `url.rstrip("/").split("/")[-1] or
    "rfc.txt"`, pinned as the constant the port falls back to.

AST, NOT GREP, for every claim about the reference; BY NAME, NOT BY LINE, for
every claim about the port.
"""
from __future__ import annotations

import ast
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER = REPO / "scripts" / "rfc_to_implementation.py"
COVER = REPO / "scripts" / "driver_ll_cover.py"
DRIVER_LL = REPO / "tools" / "llmll-driver"
SEQUENCER = DRIVER_LL / "sequencer.llmll"
REGISTRY = DRIVER_LL / "registry.llmll"

TREE = ast.parse(DRIVER.read_text(), filename=str(DRIVER))


def _uncommented(path: pathlib.Path) -> str:
    return "\n".join(line.split(";;")[0] for line in
                     path.read_text().splitlines())


SEQ = _uncommented(SEQUENCER)
REG = _uncommented(REGISTRY)


def _defs(src: str) -> dict[str, str]:
    heads = list(re.finditer(r"^\s*\((?:def-shell|def-main|def|type)\s+([\w?!-]+)", src, re.M))
    out: dict[str, str] = {}
    for h, nxt in zip(heads, heads[1:] + [None]):
        out[h.group(1)] = src[h.start():(nxt.start() if nxt else len(src))]
    return out


SEQ_DEFS = _defs(SEQ)
REG_DEFS = _defs(REG)


def _fn(name: str) -> ast.FunctionDef:
    for node in TREE.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} is not a top-level function of {DRIVER.name}")


def test_stage_a_is_ported_and_is_the_only_mechanical_stage_that_is():
    """Index 0 is true in stage-ported?; E (index 4), the other mechanical
    stage, stays a stub until a reconcile.py invocation is available. The
    sequencer routes a ported MECHANICAL stage to a-enter, not to the agent
    body, on the stage-kind table rather than on a hardcoded index."""
    ported = {int(i) for i in re.findall(r"\(if \(= i (\d+)\) true", REG_DEFS["stage-ported?"])}
    assert 0 in ported and 4 not in ported, sorted(ported)
    assert '(= (stage-kind (idx-at rn k)) "mechanical")' in SEQ_DEFS["started-step"]
    assert "(a-enter rn k" in SEQ_DEFS["started-step"]


def test_the_fetch_is_one_call_with_the_url_first():
    """`(wasi.http.get url dest)`, the URL first (LLMLL.md sec 13: both
    parameters are strings, so the reversed call type-checks and the checker
    catches only a LITERAL). One call site, in the fetch command, whose mkdir
    of 00-source precedes it because the builtin does not create dest's
    parent."""
    sites = [d for d, body in SEQ_DEFS.items() if "(wasi.http.get " in body]
    assert sites == ["a-fetch-cmd"], sites
    body = SEQ_DEFS["a-fetch-cmd"]
    assert "(wasi.http.get (a-url l) (a-dest rn l))" in body, body
    assert body.index("wasi.fs.mkdir") < body.index("wasi.http.get")


def test_the_pin_carries_the_references_four_keys():
    """`{"url": url, "file": name, "sha256": sha256_file(dest), "lines":
    text.count("\\n")}` in stage_A_intake, found as the Dict node's keys."""
    dicts = [n for n in ast.walk(_fn("stage_A_intake")) if isinstance(n, ast.Dict)
             and any(isinstance(k, ast.Constant) and k.value == "sha256" for k in n.keys)]
    assert len(dicts) == 1
    ref_keys = [k.value for k in dicts[0].keys]
    port_keys = re.findall(r'"(url|file|sha256|lines)" \(json-of-', SEQ_DEFS["a-pin"])
    assert sorted(port_keys) == sorted(ref_keys) == ["file", "lines", "sha256", "url"], (ref_keys, port_keys)
    assert '"sources"' in SEQ_DEFS["a-next"], "the document is {\"sources\": [...]}"


def test_rfc_url_is_required_and_amend_url_repeats_and_the_cover_passes_them():
    """The reference's `missing` list names --rfc-url; `--amend-url` is
    action="append". The port parses both, requires the first, and the cover
    passes --rfc-url on every run, by AST."""
    assert '(flag-value as "--rfc-url")' in SEQ_DEFS["parse-cfg"]
    assert '(flag-values as "--amend-url")' in SEQ_DEFS["parse-cfg"], "repeatable, so flag-values"
    assert "cfg-rfc-url" in SEQ_DEFS["missing-flags"]
    assert "--rfc-url is required" in SEQ_DEFS["missing-flags"]
    main_fn = _fn("main")
    consts = {n.value for n in ast.walk(main_fn) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
    assert "--rfc-url" in consts and "--amend-url" in consts
    tree = ast.parse(COVER.read_text(), filename=str(COVER))
    drive = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "drive")
    dconsts = {n.value for n in ast.walk(drive) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
    assert "--rfc-url" in dconsts and "--amend-url" in dconsts


def test_the_file_name_falls_back_to_the_references_constant():
    """`url.rstrip("/").split("/")[-1] or "rfc.txt"`: the last non-empty
    field, else the constant, found in the reference as the `or` operand."""
    fallbacks = {n.values[-1].value for n in ast.walk(_fn("stage_A_intake"))
                 if isinstance(n, ast.BoolOp) and isinstance(n.op, ast.Or)
                 and isinstance(n.values[-1], ast.Constant)}
    assert fallbacks == {"rfc.txt"}, fallbacks
    assert '"rfc.txt"' in SEQ_DEFS["source-name"]
    assert '(split-on "/" url)' in SEQ_DEFS["source-name"]
