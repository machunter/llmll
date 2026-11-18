#!/usr/bin/env python3
"""Fill the typed holes of one core module through LLMLL's hole protocol.

usage: fill.py MOD            fill every open hole of MOD.ast.json
       fill.py MOD --emit     only make MOD.ast.json from holed/MOD.llmll
       fill.py MOD --source   only write MOD.llmll (the filled source) and
                              check that it emits the same JSON-AST

The contracts are written first, in holed/MOD.llmll, with a `?name-body`
hole for each body. The bodies are in fills/MOD.sexp, one per hole, each
after a line `;; ?name-body`. For each hole this script:
  1. runs `llmll --json holes MOD.ast.json` to find the hole's pointer,
  2. gets the body's JSON-AST: it emits a copy of the holed source with only
     that hole replaced, and takes the node at the same pointer,
  3. runs `llmll --json checkout MOD.ast.json POINTER` for a token,
  4. runs `llmll --json patch MOD.ast.json REQ` with a `test` op (the hole
     is still there) and a `replace` op (the body). The compiler type-checks
     and re-verifies the module before it writes anything.
Each outcome is appended to fills/hole-log.jsonl.

The JSON-AST is the patched artifact. --source writes the readable MOD.llmll
from the holed source and the same bodies, and fails if its JSON-AST is not
the patched one, so the two never drift.
"""
import json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LLMLL = os.environ.get("LLMLL", "llmll")


def run(args):
    p = subprocess.run([LLMLL] + args, cwd=HERE, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def bodies(mod):
    text = open(os.path.join(HERE, "fills", mod + ".sexp")).read()
    out, name = {}, None
    for line in text.splitlines():
        m = re.match(r"^;; \?([A-Za-z0-9?!-]+)\s*$", line)
        if m:
            name = m.group(1)
            out[name] = []
        elif name is not None and not line.startswith(";;"):
            out[name].append(line)
    return {k: "\n".join(v).strip() for k, v in out.items()}


def holed(mod):
    return open(os.path.join(HERE, "holed", mod + ".llmll")).read()


def subst(src, fills):
    for name, body in fills.items():
        src, n = re.subn(r"\?" + re.escape(name) + r"(?![A-Za-z0-9?!-])",
                         lambda _m: body.replace("\n", "\n  "), src)
        if n != 1:
            sys.exit(f"hole ?{name}: found {n} times in the holed source")
    return src


def emit(src, tag):
    """JSON-AST of a source text, emitted next to the real modules."""
    tmp = os.path.join(HERE, f"_fill_{tag}.llmll")
    out = os.path.join(HERE, "work", "emit")
    os.makedirs(out, exist_ok=True)
    open(tmp, "w").write(src)
    try:
        rc, so, se = run(["build", os.path.basename(tmp), "--emit", "-o", out])
        if rc != 0:
            sys.exit(f"emit failed:\n{so}{se}")
        return json.load(open(os.path.join(out, f"_fill_{tag}.ast.json")))
    finally:
        os.remove(tmp)


def node(ast, pointer):
    cur = ast
    for part in pointer.strip("/").split("/"):
        cur = cur[int(part)] if isinstance(cur, list) else cur[part]
    return cur


def log(entry):
    with open(os.path.join(HERE, "fills", "hole-log.jsonl"), "a") as f:
        f.write(json.dumps(entry) + "\n")


def fill_all(mod):
    astf = mod + ".ast.json"
    if not os.path.exists(os.path.join(HERE, astf)):
        json.dump(emit(holed(mod), mod), open(os.path.join(HERE, astf), "w"), indent=1)
    rc, so, se = run(["--json", "holes", astf])
    holes = json.loads(so)
    fills = bodies(mod)
    for h in holes:
        name = h["message"].split("?", 1)[1]
        ptr = h["pointer"]
        if name not in fills:
            print(f"{mod}: no body for ?{name}; left open")
            continue
        ast = emit(subst(holed(mod), {name: fills[name]}), mod)
        value = node(ast, ptr)
        cur = json.load(open(os.path.join(HERE, astf)))
        rc, so, se = run(["--json", "checkout", astf, ptr])
        if rc != 0:
            sys.exit(f"checkout {ptr} failed: {so}{se}")
        token = json.loads(so)["token"]
        req = {"token": token, "patch": [
            {"op": "test", "path": ptr, "value": node(cur, ptr)},
            {"op": "replace", "path": ptr, "value": value}]}
        reqf = os.path.join("work", f"patch-{mod}-{name}.json")
        json.dump(req, open(os.path.join(HERE, reqf), "w"))
        t0 = time.time()
        rc, so, se = run(["--json", "patch", astf, reqf, "--require-proof"])
        secs = round(time.time() - t0, 1)
        try:
            res = json.loads(so)
        except ValueError:
            res = {"result": "unparsed", "raw": (so + se)[-600:]}
        entry = {"module": mod, "hole": name, "pointer": ptr,
                 "result": res.get("result"), "secs": secs,
                 "verification": res.get("verification"),
                 "diagnostics": res.get("diagnostics")}
        log(entry)
        print(f"{mod} ?{name} {ptr}: {res.get('result')} ({secs} s)")
        if res.get("result") != "PatchSuccess":
            print(json.dumps(res, indent=1)[:3000])
            run(["checkout", astf, "--release", token])
            sys.exit(1)


def strip_spans(x):
    if isinstance(x, dict):
        return {k: strip_spans(v) for k, v in x.items()
                if k not in ("span", "source_span", "loc", "pos", "line", "col")}
    if isinstance(x, list):
        return [strip_spans(v) for v in x]
    return x


def source(mod):
    src = subst(holed(mod), bodies(mod))
    header = (f";; GENERATED by tools/fill.py from holed/{mod}.llmll and fills/{mod}.sexp.\n"
              f";; The patched artifact is {mod}.ast.json; this file emits the same JSON-AST.\n")
    open(os.path.join(HERE, mod + ".llmll"), "w").write(header + src)
    a = strip_spans(emit(header + src, mod)["statements"])
    b = strip_spans(json.load(open(os.path.join(HERE, mod + ".ast.json")))["statements"])
    if a != b:
        sys.exit(f"{mod}.llmll and {mod}.ast.json differ")
    print(f"{mod}.llmll written; its JSON-AST equals the patched {mod}.ast.json")


if __name__ == "__main__":
    mod = sys.argv[1]
    os.makedirs(os.path.join(HERE, "work"), exist_ok=True)
    if "--emit" in sys.argv:
        json.dump(emit(holed(mod), mod), open(os.path.join(HERE, mod + ".ast.json"), "w"), indent=1)
    elif "--source" in sys.argv:
        source(mod)
    else:
        fill_all(mod)
