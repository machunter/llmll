"""DIV-VAR-1 (IMAGE-LIB-1 Rev 3, Part C) on top of the MUL-VAR-1 Rev 3 prototype.

Not an emitter. Every VC is script-built. The division pass is the Part C text read literally:
  * atoms div##k / mod##k for each distinct normal-form pair (e, d) with a non-ground divisor;
  * D0 (three implications), G (four implications per trigger t), D4 (pairwise congruence and one
    instance per pair that a MUL-VAR-1 rule changes, with the rule's equation as premise);
  * trigger set T-zero U T-literal U T-cofactor;
  * pass order: callee-post substitution (done when the VC is built), division pass, product pass;
    every polynomial of a division fact enters the product pass, so its monomials reach P;
  * limits: MUL-VAR-1's, plus 32 division pairs (refuses the constraint with nonlinear:/).
"""
import itertools
import patch_copy
patch_copy.ensure()   # mulvar_rev3.py is generated from scripts/mulvar/rev3.py; it is not committed
import mulvar_rev3 as M  # noqa: E402
from mulvar_rev3 import Refused, Unreadable, padd, pmul, pkey, is_const, const_of, INT, ARITH, REL  # noqa: E402

MAX_DIV_PAIRS = 32
DEFAULT_CFG = dict(D0=True, G=True, D4=True, Tzero=True, Tlit=True, Tcof=True,
                   tlit_rules=False,     # the other reading: T-literal also reads literals after rule substitution
                   assume_d=True,        # the recheck assumes the proved d >= 1
                   ctl_first=False,      # invariance control: an order-dependent T-cofactor (ctl_first_lit: T-literal)
                   D4rule=True)          # Rev 3's rule clause of D4. Rev 4 drops it: those facts are F9 at a division
                                         # atom (A6). The table ran with it; export_witnesses.py sets it False.
CFG = dict(DEFAULT_CFG)


def is_ground_syntax(t):
    if isinstance(t, str):
        return bool(INT.match(t))
    return t[0] in ARITH and all(is_ground_syntax(x) for x in t[1:])


def div_refusal_scan(t):
    """Part C: a ground divisor keeps its treatment (positive numeral admitted, zero or negative refused).
    A non-ground divisor is admitted here and gets the d >= 1 obligation instead. rem and quot stay refused."""
    if isinstance(t, str):
        return
    op, *a = t
    if op in ("rem", "quot"):
        raise Refused(f"nonlinear:{op}", "rem and quot stay refused")
    if op in ("/", "mod") and is_ground_syntax(a[1]):
        k = M.ground(a[1])
        if k is None or k <= 0:
            raise Refused(f"nonlinear:{op}", f"divisor {a[1]} is a ground constant <= 0")
    for x in a:
        div_refusal_scan(x)


M.refusal_scan = div_refusal_scan


class DVC(M.VC):
    def __init__(self, hyps, goal, sorts=None, ground_facts=True):
        self.cfg = dict(CFG)
        self.pairs = {}          # (pkey e, pkey d) -> (e, d)
        self.div_stats = {}
        self.div_triggers = {}   # per pair "pkey e|pkey d": the sorted trigger keys (export_witnesses.py)
        super().__init__(hyps, goal, sorts, ground_facts)

    # ------------------------------------------------------------ atoms
    def poly(self, t):
        if isinstance(t, list) and t[0] in ("/", "mod") and not is_ground_syntax(t[2]):
            e, d = self.poly(t[1]), self.poly(t[2])
            return self.mkv("vdiv" if t[0] == "/" else "vmod", e, d)
        return super().poly(t)

    def mkv(self, kind, e, d):
        pk = (pkey(e), pkey(d))
        if len(self.pairs) >= MAX_DIV_PAIRS and pk not in self.pairs:
            raise Refused("nonlinear:/", f"more than {MAX_DIV_PAIRS} division pairs")
        self.pairs.setdefault(pk, (e, d))
        key = f"{kind}[{pk[0]}|{pk[1]}]"
        self.atoms.setdefault(key, (kind, e, d))
        return {(key,): 1}

    def atoms_of(self, pk):
        e, d = self.pairs[pk]
        q = list(self.mkv("vdiv", e, d))[0][0]
        r = list(self.mkv("vmod", e, d))[0][0]
        return q, r

    def atom_contains(self, v, a):
        d = self.atoms[a]
        if d[0] in ("vdiv", "vmod"):
            return self.contains(v, d[1]) or self.contains(v, d[2])
        return super().atom_contains(v, a)

    def subst_atom(self, a, x, e):
        d = self.atoms.get(a)
        if a != x and d and d[0] in ("vdiv", "vmod"):
            if not self.atom_contains(x, a):
                return {(a,): 1}
            return self.mkv(d[0], self.subst(d[1], x, e), self.subst(d[2], x, e))
        return super().subst_atom(a, x, e)

    def inner_polys(self, a):
        d = self.atoms[a]
        if d[0] in ("vdiv", "vmod"):
            return [d[1], d[2]]
        return super().inner_polys(a)

    def pair_index(self):
        return {pk: i for i, pk in enumerate(sorted(self.pairs))}

    def patom(self, a, mode):
        d = self.atoms[a]
        if d[0] in ("vdiv", "vmod"):
            k = self.pair_index()[(pkey(d[1]), pkey(d[2]))]
            nm = "div" if d[0] == "vdiv" else "mod"
            if mode == "fq":
                return f"{nm}##{k}"
            if mode == "smt":
                return f"{nm}_{k}"
            return f"({'div' if nm == 'div' else 'mod'} {self.ppoly(d[1], mode)} {self.ppoly(d[2], mode)})"
        return super().patom(a, mode)

    def extra_decls(self, mode):
        n = len(self.pairs)
        if mode == "fq":
            return [f"{nm}##{k}" for k in range(n) for nm in ("div", "mod")]
        return [f"(declare-const {nm}_{k} Int)" for k in range(n) for nm in ("div", "mod")]

    def native_extra(self):
        if not self.cfg["assume_d"]:
            return []
        return [f"(>= {self.ppoly(d, 'nat')} 1)" for (_, d) in (self.pairs[k] for k in sorted(self.pairs)) if not is_const(d)]

    def val_atom(self, a, env, fns):
        d = self.atoms[a]
        if d[0] in ("vdiv", "vmod"):
            x, y = self.val_poly(d[1], env, fns), self.val_poly(d[2], env, fns)
            if y == 0:
                raise Unreadable("division by zero")
            return x // y if d[0] == "vdiv" else x % y      # Python // and % are Haskell div and mod
        return super().val_atom(a, env, fns)

    def s_atom(self, a, ren):
        d = self.atoms[a]
        if d[0] in ("vdiv", "vmod"):
            return (d[0], self.s_poly(d[1], ren), self.s_poly(d[2], ren))
        return super().s_atom(a, ren)

    # ------------------------------------------------------------ ablation of D4: F9 links through a division atom are D4's job
    def skip_f9(self, m, rule):
        if self.cfg.get("F9div", True):
            return False
        return any(self.atoms[a][0] in ("vdiv", "vmod") and self.atom_contains(rule[0], a) for a in m)

    # ------------------------------------------------------------ the division pass
    def literals(self):
        out = []

        def walk(t):
            if isinstance(t, str):
                return
            op, *a = t
            if op in REL:
                out.append((op, padd(self.poly(a[0]), self.poly(a[1]), -1)))
            for x in a:
                walk(x)
        for h in self.hyps + [self.goal]:
            walk(h)
        if self.cfg["tlit_rules"]:
            seen = {(o, pkey(p)) for o, p in out}
            todo = list(out)
            while todo:
                o, p = todo.pop()
                for rule in self.relevant_rules(p):
                    p2 = self.subst(p, rule[0], rule[1])
                    if (o, pkey(p2)) not in seen and len(seen) < 512:
                        seen.add((o, pkey(p2)))
                        out.append((o, p2))
                        todo.append((o, p2))
        return out

    def pre_facts(self):
        coll = {"polys": [], "written": []}
        for h in self.hyps:
            self.walk_terms(h, coll)
        self.walk_terms(self.goal, coll)
        lits = self.literals()
        # 1. pairs: those written, then each pair a MUL-VAR-1 rule changes, to a fixed point
        d4rule = []
        todo, done = sorted(self.pairs), set()
        while todo:
            pk = todo.pop(0)
            if pk in done:
                continue
            done.add(pk)
            e, d = self.pairs[pk]
            rules = {(r[0], pkey(r[1])): r for r in self.relevant_rules(e) + self.relevant_rules(d)}
            for _, rule in sorted(rules.items()):
                e2, d2 = self.subst(e, rule[0], rule[1]), self.subst(d, rule[0], rule[1])
                self.mkv("vdiv", e2, d2)
                pk2 = (pkey(e2), pkey(d2))
                if pk2 != pk:
                    d4rule.append((rule, pk, pk2))
                    if pk2 not in done:
                        todo.append(pk2)
        keys = sorted(self.pairs)
        for pk in keys:
            self.atoms_of(pk)
        # 2. the monomials of the MUL-VAR-1 closure of the constraint as written, for T-cofactor
        seeds = self.monos_deep(coll["polys"])
        graph = self.closure(seeds)
        monos = set(graph) | set(seeds)
        out = []
        zero, one = {}, {(): 1}

        def rel(op, l, r):
            return (op, padd(l, r, -1))
        ntrig = {"Tzero": 0, "Tlit": 0, "Tcof": 0}
        for pk in keys:
            e, d = self.pairs[pk]
            q, r = self.atoms_of(pk)
            Q, R = {(q,): 1}, {(r,): 1}
            dge1 = rel(">=", d, one)
            if self.cfg["D0"]:
                out.append(("D0", [dge1], rel("=", e, padd(pmul(d, Q), R))))
                out.append(("D0", [dge1], rel(">=", R, zero)))
                out.append(("D0", [dge1], rel("<=", R, padd(d, one, -1))))
            trig = {}
            if self.cfg["Tzero"]:
                trig.setdefault(pkey(zero), (zero, set()))[1].add("Tzero")
            if self.cfg["Tlit"]:
                used = 0
                for o, p in lits:
                    c = p.get((q,), 0)
                    if c in (1, -1) and self.cfg.get("ctl_first_lit") and used:
                        continue          # invariance control only: first matching literal in conjunct order
                    if c in (1, -1):
                        used += 1
                        rest = padd(p, {(q,): c}, -1)
                        u = padd({}, rest, -c)
                        trig.setdefault(pkey(u), (u, set()))[1].add("Tlit")
                        if o in ("<", ">"):
                            u1 = padd(u, one, -1)
                            trig.setdefault(pkey(u1), (u1, set()))[1].add("Tlit")
            if self.cfg["Tcof"] and len(d) == 1 and list(d.values())[0] == 1 and list(d)[0]:
                md = list(d)[0]
                cands = sorted(monos)
                if self.cfg.get("ctl_first"):
                    # invariance control only: the first divisible monomial of degree >= 2 in conjunct order
                    order = []
                    for _, p0 in lits:
                        for m0 in p0:
                            if m0 not in order:
                                order.append(m0)
                    cands = [m0 for m0 in order if len(m0) > len(md) and all(m0.count(a0) >= md.count(a0) for a0 in md)][:1]
                for m in cands:
                    rest = list(m)
                    ok = True
                    for a in md:
                        if a in rest:
                            rest.remove(a)
                        else:
                            ok = False
                            break
                    if ok:
                        t = padd({tuple(rest): 1}, one, -1)
                        trig.setdefault(pkey(t), (t, set()))[1].add("Tcof")
            self.div_triggers[f"{pk[0]}|{pk[1]}"] = sorted(trig)
            for _, (t, srcs) in sorted(trig.items()):
                for s_ in srcs:
                    ntrig[s_] += 1
                if not self.cfg["G"]:
                    continue
                dt = pmul(d, t)
                hi = padd(padd(dt, d), one, -1)          # d*t + d - 1
                out.append(("G", [dge1, rel("<=", dt, e)], rel("<=", t, Q)))
                out.append(("G", [dge1, rel("<=", t, Q)], rel("<=", dt, e)))
                out.append(("G", [dge1, rel("<=", Q, t)], rel("<=", e, hi)))
                out.append(("G", [dge1, rel("<=", e, hi)], rel("<=", Q, t)))
        if self.cfg["D4"]:
            for k1, k2 in itertools.combinations(keys, 2):
                (e1, d1), (e2, d2) = self.pairs[k1], self.pairs[k2]
                q1, r1 = self.atoms_of(k1)
                q2, r2 = self.atoms_of(k2)
                prem = [rel("=", e1, e2), rel("=", d1, d2)]
                out.append(("D4", prem, rel("=", {(q1,): 1}, {(q2,): 1})))
                out.append(("D4", prem, rel("=", {(r1,): 1}, {(r2,): 1})))
            for rule, k1, k2 in (d4rule if self.cfg.get("D4rule", True) else []):
                q1, r1 = self.atoms_of(k1)
                q2, r2 = self.atoms_of(k2)
                out.append(("D4", [("=", rule[2])], rel("=", {(q1,): 1}, {(q2,): 1})))
                out.append(("D4", [("=", rule[2])], rel("=", {(r1,): 1}, {(r2,): 1})))
        self.div_stats = dict(pairs=len(keys), triggers=ntrig, d4rule=len(d4rule))
        self.pairs_after_pass = len(self.pairs)
        return out


M.VC_FACTORY = DVC
