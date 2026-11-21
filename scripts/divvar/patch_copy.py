"""Writes mulvar_rev3.py beside this file: scripts/mulvar/rev3.py plus the DIV-VAR-1 hooks, each marked DIV-VAR-1.

scripts/mulvar/rev3.py stays byte-identical. The patched copy is generated at run time (divvar_core.py calls
ensure() before it imports mulvar_rev3) and is not committed. Run directly to regenerate it:
    python3 scripts/divvar/patch_copy.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "mulvar", "rev3.py")
OUT = os.path.join(HERE, "mulvar_rev3.py")
s = open(SRC).read()
def rep(a, b, n=1):
    global s
    c = s.count(a)
    assert c == n, (a, c)
    s = s.replace(a, b)

rep('SOLVER_CALLS = {"z3": 0, "fixpoint": 0}\n',
    'SOLVER_CALLS = {"z3": 0, "fixpoint": 0}\nVC_FACTORY = None   # DIV-VAR-1: divvar.py installs its subclass here\n\n\ndef mkvc(*a, **k):\n    return (VC_FACTORY or VC)(*a, **k)\n')
rep('    if op == "/": return v[0] // v[1]\n    if op == "mod": return v[0] % v[1]\n    if op == "abs"',
    '    if op in ("/", "mod") and v[1] == 0:\n        raise Unreadable("division by zero")   # DIV-VAR-1\n    if op == "/": return v[0] // v[1]\n    if op == "mod": return v[0] % v[1]\n    if op == "abs"')
rep('    vc = VC(hyps, goal, sorts)\n    fx = vc.facts()\n    facts = sorted(vc.pfact(f, "smt") for f in fx)',
    '    vc = mkvc(hyps, goal, sorts)\n    fx = vc.facts()\n    facts = sorted(vc.pfact(f, "smt") for f in fx)')
rep('    head = decls_smt(vc, vs)\n    if MONO == "uf":',
    '    head = decls_smt(vc, vs) + (vc.extra_decls("smt") if hasattr(vc, "extra_decls") else [])   # DIV-VAR-1\n    if MONO == "uf":')
rep('    vc = VC(hyps, goal, sorts)\n    fx = vc.facts()\n    facts = sorted(vc.pfact(f, "fq") for f in fx)',
    '    vc = mkvc(hyps, goal, sorts)\n    fx = vc.facts()\n    facts = sorted(vc.pfact(f, "fq") for f in fx)')
rep('        bind.append((v, f"{{ v : {fq_sort(vc.sorts.get(v, \'Int\'))} | true }}"))\n',
    '        bind.append((v, f"{{ v : {fq_sort(vc.sorts.get(v, \'Int\'))} | true }}"))\n    if hasattr(vc, "extra_decls"):   # DIV-VAR-1: div##k and mod##k are environment binders\n        bind += [(n, "{ v : int | true }") for n in vc.extra_decls("fq")]\n')
rep('    vc = VC(hyps, goal, sorts, ground_facts=ground_facts)',
    '    vc = mkvc(hyps, goal, sorts, ground_facts=ground_facts)')
rep('    body.append(f"(assert (not {vc.pform(goal, \'nat\')}))")\n    head = decls_smt(vc, vs)\n    if rlimit:',
    '    body += [f"(assert {x})" for x in (vc.native_extra() if hasattr(vc, "native_extra") else [])]   # DIV-VAR-1: the proved d >= 1\n    body.append(f"(assert (not {vc.pform(goal, \'nat\')}))")\n    head = decls_smt(vc, vs)\n    if rlimit:')
# facts(): division facts first, their polynomials enter the closure and P
rep('''        for h in self.hyps:
            self.walk_terms(h, coll)
        self.walk_terms(self.goal, coll)
        F = {}
''', '''        for h in self.hyps:
            self.walk_terms(h, coll)
        self.walk_terms(self.goal, coll)
        pre = self.pre_facts() if hasattr(self, "pre_facts") else []   # DIV-VAR-1: the division pass runs before the product pass
        for _, ps0, c0 in pre:
            coll["polys"].extend([p0 for _, p0 in ps0] + [c0[1]])
        F = {}
''')
rep('''        seeds = self.monos_deep(coll["polys"])
        graph = self.closure(seeds)''', '''        for fam0, ps0, c0 in pre:
            add(fam0, ps0, c0)
        seeds = self.monos_deep(coll["polys"])
        graph = self.closure(seeds)''')
rep('''            for rule, q in graph[m]:
                add("F9", [("=", rule[2])], rel("=", {m: 1}, q))''', '''            for rule, q in graph[m]:
                if hasattr(self, "skip_f9") and self.skip_f9(m, rule):   # DIV-VAR-1 ablation only
                    continue
                add("F9", [("=", rule[2])], rel("=", {m: 1}, q))''')
rep('''        if not self.val_rel(o, p, env, fns):
                return None''','''        if not self.val_rel(o, p, env, fns):
                return None''', 0) if False else None
s = s.replace('"""MUL-VAR-1 Rev 3 prototype', '"""[divvar copy: verbatim scripts/mulvar/rev3.py plus hooks marked DIV-VAR-1]\nMUL-VAR-1 Rev 3 prototype', 1)
PATCHED = s


def ensure():
    """Write OUT if it is missing or differs from a fresh patch of SRC."""
    if not os.path.exists(OUT) or open(OUT).read() != PATCHED:
        with open(OUT, "w") as f:
            f.write(PATCHED)
    return OUT


if __name__ == "__main__":
    print("ok", ensure())
