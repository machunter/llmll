#!/usr/bin/env python3
"""Convert a fill-agent reply (FILL/REFINE + s-exprs) into an llmll patch/refine
request JSON, using the compiler's own parser via `llmll build --emit` on a
temp module (no hand-rolled s-expr -> JSON-AST conversion).

Usage: convert_reply.py <brief-given.json> <token-file> <reply.txt> <out-req.json>
Prints the operation to run ("patch" or "refine") on stdout.
"""
import json, subprocess, sys, tempfile, os

import os as _os
_BIN = _os.environ.get("LLMLL_BIN")
STACK = [_BIN] if _BIN else ["stack", "--stack-yaml",
         "/Users/burcsahinoglu/Documents/llmll/compiler/stack.yaml",
         "exec", "llmll", "--"]

def main():
    brief_p, token_p, reply_p, out_p = sys.argv[1:5]
    brief = json.load(open(brief_p))
    token = open(token_p).read().strip()
    reply = open(reply_p).read().strip()

    lines = reply.splitlines()
    mode = lines[0].strip()
    assert mode in ("FILL", "REFINE"), f"bad mode line: {lines[0]!r}"
    rest = "\n".join(lines[1:]).strip()

    # Split body s-expr from spawned (def-shell ...) blocks by top-level parens.
    # A4 pilot finding: a BARE-ATOM body (e.g. `tid` — a legal LLMLL expression)
    # has no parens and used to trip the trailing-content assert; admit a single
    # leading atom as the body chunk before paren-chunking the rest.
    chunks, depth, cur = [], 0, []
    if rest and not rest.startswith("("):
        atom, _, remainder = rest.partition("\n")
        atom = atom.strip()
        assert "(" not in atom and ")" not in atom, f"malformed body line: {atom!r}"
        chunks.append(atom)
        rest = remainder.strip()
    for ch in rest:
        cur.append(ch)
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                chunks.append("".join(cur).strip())
                cur = []
    tail = "".join(cur).strip()
    assert not tail, f"trailing non-s-expr content: {tail!r}"
    body_sexp = chunks[0]
    spawns = chunks[1:]
    if mode == "FILL":
        assert not spawns, "FILL reply must contain exactly one s-expression"
    for s in spawns:
        assert s.startswith("(def-shell"), f"spawn is not a def-shell: {s[:40]}"

    # The enclosing function (status "hole") gives wrapper params + return type.
    hole_fns = [f for f in brief["available_functions"] if f["status"] == "hole"]
    assert len(hole_fns) == 1, f"expected exactly one hole fn, got {hole_fns}"
    hf = hole_fns[0]
    params = " ".join(f"{p['name']}: {p['type']}" for p in hf["params"])

    # Temp module: spawned defs first (so the wrapper body's calls resolve),
    # wrapper last. No contracts on the wrapper (conversion only).
    src = "\n".join(spawns) + f"\n(def-shell __conv [{params}] -> {hf['return_type']}\n  {body_sexp})\n"
    with tempfile.TemporaryDirectory() as td:
        mod = os.path.join(td, "conv.llmll")
        open(mod, "w").write(src)
        r = subprocess.run(STACK + ["build", mod, "--emit"],
                           capture_output=True, text=True, cwd=td)
        ast_p = os.path.join(td, "generated", "conv", "conv.ast.json")
        if not os.path.exists(ast_p):
            sys.stderr.write("CONVERSION-BUILD-FAILED\n" + r.stdout + r.stderr)
            sys.exit(2)
        ast = json.load(open(ast_p))

    stmts = ast["statements"]
    body_json = stmts[-1]["body"]
    spawn_json = stmts[:-1]

    req = {"token": token,
           "patch": [{"op": "replace", "path": brief["pointer"], "value": body_json}]
                    + [{"op": "add", "path": "/statements/-", "value": s}
                       for s in spawn_json]}
    json.dump(req, open(out_p, "w"), indent=1)
    print("refine" if spawns else "patch")

if __name__ == "__main__":
    main()
