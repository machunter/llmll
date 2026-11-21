"""Functions, VC construction (callee-post substitution, PROVE obligations, CLAUSE-WELLDEF pi), mutants, oracle."""
import itertools
import json
import time

import divvar_core as D
import mulvar_rev3 as M
from mulvar_rev3 import Refused, Unreadable, INT, REL

P = M.parse
RASTER = "(and (>= w 1) (and (>= h 1) (and (or (= c 1) (= c 3)) (and (<= (* (* w h) c) 268435456) (= (bytes-length buf) (* (* w h) c))))))"
GEOM_PRE = "(and (>= w 1) (and (>= c 1) (and (>= h 1) (and (>= i 0) (< i (* (* w h) c))))))"
HFLIP_IDX = "(+ (* (+ (* (/ i (* w c)) w) (- (- w 1) (/ (mod i (* w c)) c))) c) (mod i c))"

FUNS = {
    "offset": dict(params="w h c y x k",
                   pre="(and (>= w 1) (and (>= h 1) (and (>= c 1) (and (>= y 0) (and (< y h) (and (>= x 0) (and (< x w) (and (>= k 0) (< k c)))))))))",
                   post="(and (= result (+ (* (+ (* y w) x) c) k)) (and (>= result 0) (< result (* (* w h) c))))",
                   body="(+ (* (+ (* y w) x) c) k)"),
    "row-of": dict(params="w c h i", pre=GEOM_PRE,
                   post="(and (= result (/ i (* w c))) (and (>= result 0) (< result h)))",
                   body="(/ i (* w c))", example="(/ i w)"),
    "col-of": dict(params="w c h i", pre=GEOM_PRE,
                   post="(and (= result (/ (mod i (* w c)) c)) (and (>= result 0) (< result w)))",
                   body="(/ (mod i (* w c)) c)", example="(mod i w)"),
    "chan-of": dict(params="c i", pre="(and (>= c 1) (>= i 0))",
                    post="(and (= result (mod i c)) (and (>= result 0) (< result c)))",
                    body="(mod i c)", example="(/ i c)"),
    "hflip-x": dict(params="w x", pre="(and (>= w 1) (and (>= x 0) (< x w)))",
                    post="(= result (- (- w 1) x))", body="(- (- w 1) x)"),
    "scale-src": dict(params="sw dw x", pre="(and (>= sw 1) (and (>= dw 1) (and (>= x 0) (< x dw))))",
                      post="(and (= result (/ (* x sw) dw)) (and (>= result 0) (< result sw)))",
                      body="(/ (* x sw) dw)", example="(/ (* (+ x 1) sw) dw)"),
    "hflip-at": dict(params="buf w h c i", sorts={"buf": "bytes"},
                     pre=f"(and {RASTER} (and (>= i 0) (< i (bytes-length buf))))",
                     post=f"(= result (bytes-get buf {HFLIP_IDX}))",
                     body="(let ((y (row-of w c h i)) (x (col-of w c h i)) (k (chan-of c i)) (xf (hflip-x w x)) (j (offset w h c y xf k))) (bytes-get buf j))",
                     example="(bytes-get buf i)", byte=True),
}
CALLEES = {k: FUNS[k] for k in ("offset", "row-of", "col-of", "chan-of", "hflip-x")}


def sub(t, m):
    if isinstance(t, str):
        return m.get(t, t)
    return [t[0]] + [sub(x, m) for x in t[1:]]


def show(t):
    return t if isinstance(t, str) else "(" + " ".join(show(x) for x in t) + ")"


def leaves(t, out):
    if isinstance(t, str):
        if not INT.match(t):
            out.add(t)
        return out
    for x in t[1:]:
        leaves(x, out)
    return out


def flat_and(t):
    if isinstance(t, list) and t[0] == "and":
        return [y for x in t[1:] for y in flat_and(x)]
    return [t]


class Lower:
    """Callee-post substitution and PROVE obligations, in the emitter's shape: a let is a binder equation,
    a shadowing let gets a fresh _bv_ name, a call gets a fresh result binder with the callee post assumed."""

    def __init__(self, params, sorts, callees):
        self.hyps, self.obl, self.scope, self.n = [], [], set(params), 0
        self.sorts, self.callees = dict(sorts), callees

    def fresh(self, base):
        self.n += 1
        return f"{base}_{self.n}"

    def term(self, t, env):
        if isinstance(t, str):
            return t if INT.match(t) else env.get(t, t)
        op, *a = t
        if op == "let":
            env2 = dict(env)
            for name, ex in a[0]:
                v = self.term(ex, env2)
                nm = name if name not in self.scope else f"_bv_{name}_{self.n}"
                self.n += 1
                self.scope.add(nm)
                self.hyps.append(["=", nm, v])
                env2[name] = nm
            return self.term(a[1], env2)
        if op in self.callees:
            f = self.callees[op]
            args = [self.term(x, env) for x in a]
            m = dict(zip(f["params"].split(), args))
            self.obl.append(("call-pre:" + op, list(self.hyps), sub(P(f["pre"]), m)))
            r = self.fresh("call_" + op.replace("-", "_"))
            m["result"] = r
            self.hyps.append(sub(P(f["post"]), m))
            return r
        if op == "bytes-get":
            b, j = self.term(a[0], env), self.term(a[1], env)
            self.obl.append(("read", list(self.hyps), ["and", [">=", j, "0"], ["<", j, ["bytesLen", b]]]))
            return ["select", b, j]
        if op == "bytes-length":
            return ["bytesLen", self.term(a[0], env)]
        args = [self.term(x, env) for x in a]
        if op in ("/", "mod") and not D.is_ground_syntax(args[1]):
            self.obl.append(("div:" + op, list(self.hyps), [">=", args[1], "1"]))
        return [op] + args


def clause(t, ctx, pis):
    """Lower a clause; collect CLAUSE-WELLDEF pi obligations with their context C (earlier conjuncts, antecedents)."""
    if isinstance(t, str):
        return t
    op, *a = t
    if op == "and":
        out, c = [], list(ctx)
        for x in a:
            y = clause(x, c, pis)
            out.append(y)
            c = c + [y]
        return ["and"] + out
    if op == "=>":
        x = clause(a[0], ctx, pis)
        y = clause(a[1], ctx + [x], pis)
        return ["=>", x, y]
    if op in ("or",):
        return [op] + [clause(x, ctx, pis) for x in a]
    args = [clause(x, ctx, pis) for x in a]
    if op == "bytes-get":
        pis.append(("wd:read", list(ctx), ["and", [">=", args[1], "0"], ["<", args[1], ["bytesLen", args[0]]]]))
        return ["select"] + args
    if op == "bytes-length":
        return ["bytesLen"] + args
    if op in ("/", "mod") and not D.is_ground_syntax(args[1]):
        pis.append(("wd:" + op, list(ctx), [">=", args[1], "1"]))
    return [op] + args


def vcs_of(f, body=None, wd=True, wd_pre_only=False):
    """List of (tag, kind, hyps, goal, sorts). kind: TRUTH, BODY, WD."""
    params = f["params"].split()
    sorts = f.get("sorts", {})
    body = P(body or f["body"])
    pis_pre = []
    pre = clause(P(f["pre"]), [], pis_pre) if f.get("pre") else None
    L = Lower(params + ["result"], sorts, CALLEES)
    t = L.term(body, {})
    H = ([pre] if pre else [])
    out = []
    for tag, hs, g in L.obl:
        out.append((tag, "BODY", H + hs, g, sorts))
    pis = []
    post = clause(P(f["post"]), [], pis)
    truthH = H + L.hyps + [["=", "result", t]]
    out.append(("truth", "TRUTH", truthH, post, sorts))
    if wd:
        for tag, c, g in pis:
            out.append((tag.replace("wd:", "wd-post:"), "WD", truthH + c, g, sorts))
            if wd_pre_only:
                out.append((tag.replace("wd:", "wd-post(pre-only):"), "WD", H + c, g, sorts))
        for tag, c, g in pis_pre:
            out.append((tag.replace("wd:", "wd-pre:"), "WD", list(c), g, sorts))
    return out


def vars_of(hyps, goal):
    s = set()
    for h in hyps + [goal]:
        leaves(h, s)
    s -= {"true", "false"}
    return " ".join(sorted(s))


# ---------------------------------------------------------------- running one VC
def run_vc(hyps, goal, sorts, cfg=None, tmo=120, z3check=True, recheck=True):
    D.CFG.clear()
    D.CFG.update(D.DEFAULT_CFG, **(cfg or {}))
    vs = vars_of(hyps, goal)
    w = M.W(vs, [], "true")
    vs = w[0]
    out = {}
    try:
        t0 = time.process_time()
        q, vc, fx = M.build_fq(vs, hyps, goal, sorts or None)
        out["gen_cpu"] = round(time.process_time() - t0, 3)
    except Refused as e:
        out.update(verdict="refused", construct=e.construct, why=e.why, facts=0, T=0, dpairs=0, cpu=0.0)
        return out
    fam = {}
    for f in fx:
        fam[f[0]] = fam.get(f[0], 0) + 1
    out.update(facts=len(fx), fam=fam, T=vc.T, capped=vc.capped, dpairs=len(vc.pairs),
               dpairs_pass=getattr(vc, "pairs_after_pass", 0), div=vc.div_stats, closure=vc.closure_size, maxdeg=vc.max_deg)
    if vc.rhs_true:
        r, c = "SAFE-NF", 0.0
    else:
        r, c = M.fixpoint(q, tmo)
    out.update(fp=r, cpu=c)
    if z3check:
        s, _, _ = M.build_smt(vs, hyps, goal, sorts or None)
        z, zs = M.z3_run(s, 30)
        out["z3"] = z.strip().split("\n")[0] if z.strip() else "empty"
    if r.startswith("SAFE"):
        out["verdict"] = "verified"
    elif r == "UNSAFE":
        if recheck:
            rc = M.recheck(vs, hyps, goal, sorts or None)
            out["rc_assume_d"] = True
            if not (rc[0] == "sat" and rc[3] == "validated"):
                # the d >= 1 assumption holds only where it was proved; retry without it. The validator reads
                # every / and mod as Haskell div and mod itself, so either query's validated model is a counterexample.
                D.CFG["assume_d"] = False
                rc2 = M.recheck(vs, hyps, goal, sorts or None)
                D.CFG["assume_d"] = True
                out["rc_first"] = [rc[0], rc[3]]
                if rc2[0] == "sat" and rc2[3] == "validated":
                    rc, out["rc_assume_d"] = rc2, False
            out.update(rc=rc[0], rc_model=rc[3], rl=rc[2])
            if rc[0] == "sat" and rc[3] == "validated":
                out["verdict"] = "refuted"
                det = rc[4]
                out["cex"] = {k: (v if isinstance(v, int) else repr(v)) for k, v in det["env"].items()}
            else:
                out["verdict"] = "fallback"
        else:
            out["verdict"] = "fallback"
    else:
        out["verdict"] = "no-result"
    return out


def combine(results):
    """Function outcome from its VCs (tag, kind, result)."""
    ks = lambda k: [r for t, kk, r in results if kk == k]
    if any(r["verdict"] == "refuted" for r in ks("TRUTH") + ks("BODY")):
        return "refuted"
    if any(r["verdict"] == "refuted" for r in ks("WD")):
        return "ill-defined"
    if any(r["verdict"] == "refused" for _, _, r in results):
        return "fallback(refused)"
    if any(r["verdict"] != "verified" for _, _, r in results):
        return "fallback"
    return "verified"


# ---------------------------------------------------------------- mutants (Part D operator set, on the body)
AOPS = ["+", "-", "*", "/", "mod"]


def paths(t, p=()):
    yield p, t
    if isinstance(t, list):
        if t[0] == "let":
            for i, (nm, ex) in enumerate(t[1]):
                yield from paths(ex, p + (("let", i),))
            yield from paths(t[2], p + (2,))
        else:
            for i, x in enumerate(t[1:], 1):
                yield from paths(x, p + (i,))


def put(t, p, v):
    if not p:
        return v
    h, rest = p[0], p[1:]
    t = list(t)
    if isinstance(h, tuple):
        binds = [list(b) for b in t[1]]
        binds[h[1]][1] = put(binds[h[1]][1], rest, v)
        t[1] = binds
    else:
        t[h] = put(t[h], rest, v)
    return t


def mutants(f):
    body = P(f["body"])
    params = f["params"].split()
    sorts = f.get("sorts", {})
    ints = [x for x in params if sorts.get(x, "Int") == "Int"]
    out = []
    for p, t in paths(body):
        if isinstance(t, str):
            if INT.match(t):
                for dlt in (1, -1):
                    out.append(("constant", put(body, p, str(int(t) + dlt))))
            elif sorts.get(t, "Int") == "Int":
                out.append(("index+1", put(body, p, ["+", t, "1"])))
                out.append(("index-1", put(body, p, ["-", t, "1"])))
            continue
        op = t[0]
        if op in REL:
            for o in REL:
                if o != op:
                    out.append(("ROR", put(body, p, [o] + t[1:])))
        if op in AOPS and len(t) == 3:
            for o in AOPS:
                if o != op:
                    out.append(("AOR " + op + "->" + o, put(body, p, [o] + t[1:])))
        if op == "*":
            for x in t[1:]:
                out.append(("factor-deletion", put(body, p, x)))
        if op in ("-", "/", "mod") and len(t) == 3:
            out.append(("swap", put(body, p, [op, t[2], t[1]])))
        if op in CALLEES:
            cp = CALLEES[op]["params"].split()
            for i, j in itertools.combinations(range(1, len(t)), 2):
                out.append(("swap", put(body, p, t[:i] + [t[j]] + t[i + 1:j] + [t[i]] + t[j + 1:])))
        if op == "bytes-get":
            out.append(("index+1", put(body, p, [op, t[1], ["+", t[2], "1"]])))
            out.append(("index-1", put(body, p, [op, t[1], ["-", t[2], "1"]])))
    out.append(("identity", ints[0]))
    out.append(("constant-result", "0"))
    if f.get("byte"):
        out.append(("constant-result", "255"))
    seen, res = {show(body)}, []
    for lab, m in out:
        s = show(m)
        if s not in seen:
            seen.add(s)
            res.append((lab, s))
    ex = f.get("example")
    gen = ex is None or any(s == show(P(ex)) for _, s in res)
    if ex is not None and not gen:
        res.append(("table-example (not generated)", show(P(ex))))
    return res, gen


# ---------------------------------------------------------------- the oracle: Haskell semantics, exhaustive on a small domain
class Viol(Exception):
    pass


class Buf:
    def __init__(self, vals):
        self.v = vals


def ev(t, env, funs):
    if isinstance(t, str):
        if INT.match(t):
            return int(t)
        return env[t]
    op, *a = t
    if op == "let":
        e2 = dict(env)
        for nm, ex in a[0]:
            e2[nm] = ev(ex, e2, funs)
        return ev(a[1], e2, funs)
    if op in ("and", "or", "=>", "not"):
        if op == "and":
            return all(ev(x, env, funs) for x in a)
        if op == "or":
            return any(ev(x, env, funs) for x in a)
        if op == "not":
            return not ev(a[0], env, funs)
        return (not ev(a[0], env, funs)) or ev(a[1], env, funs)
    v = [ev(x, env, funs) for x in a]
    if op in funs:
        f = funs[op]
        e2 = dict(zip(f["params"].split(), v))
        if not ev(P(f["pre"]), e2, funs):
            raise Viol("call-pre " + op)
        return ev(P(f["body"]), e2, funs)
    if op == "bytes-get":
        if not (0 <= v[1] < len(v[0].v)):
            raise Viol("read")
        return v[0].v[v[1]]
    if op == "bytes-length":
        return len(v[0].v)
    if op in ("/", "mod"):
        if v[1] < 1:
            raise Viol("divisor < 1")
        return v[0] // v[1] if op == "/" else v[0] % v[1]
    return {"+": lambda: sum(v), "-": lambda: v[0] - sum(v[1:]), "*": lambda: v[0] * v[1],
            "<": lambda: v[0] < v[1], "<=": lambda: v[0] <= v[1], ">": lambda: v[0] > v[1],
            ">=": lambda: v[0] >= v[1], "=": lambda: v[0] == v[1], "!=": lambda: v[0] != v[1]}[op]()


def domain(name):
    if name in ("row-of", "col-of", "row-of-stride"):
        for w, c, h in itertools.product(range(1, 5), range(1, 5), range(1, 4)):
            for i in range(w * h * c):
                yield dict(w=w, c=c, h=h, i=i)
    elif name == "chan-of":
        for c in range(1, 6):
            for i in range(25):
                yield dict(c=c, i=i)
    elif name == "scale-src":
        for sw, dw in itertools.product(range(1, 6), range(1, 7)):
            for x in range(dw):
                yield dict(sw=sw, dw=dw, x=x)
    elif name == "hflip-at":
        for w, h, c in itertools.product(range(1, 4), range(1, 4), (1, 3)):
            buf = Buf([(j * 37 + 11) % 256 for j in range(w * h * c)])
            for i in range(w * h * c):
                yield dict(buf=buf, w=w, h=h, c=c, i=i)


def oracle(name, f, mbody):
    """'equivalent', or 'differs at {...}' with the first witness."""
    pre, post = P(f["pre"]), P(f["post"])
    for env in domain(name):
        if not ev(pre, env, CALLEES):
            continue
        o = ev(P(f["body"]), env, CALLEES)
        e2 = dict(env, result=o)
        assert ev(post, e2, CALLEES), (name, env)
        try:
            m = ev(P(mbody), env, CALLEES)
        except Viol as x:
            return f"undefined ({x}) at " + json.dumps({k: v for k, v in env.items() if k != 'buf'})
        if m != o:
            return f"differs at " + json.dumps({k: v for k, v in env.items() if k != 'buf'}) + f" ({m} vs {o})"
    return "equivalent"
