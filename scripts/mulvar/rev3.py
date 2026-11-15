#!/usr/bin/env python3
"""MUL-VAR-1 Rev 3 prototype and measurements. One file, standard library only, no arguments, no local paths.
Needs `z3` and `fixpoint` on PATH. Writes results to stdout and r_rev3.json in the current folder.

Not an emitter: every VC is hand-built from a witness. Nothing goes through `llmll verify`.
Printing here is the flat printing that FQ-ARITH-FLAT-1 must ship first.
"""
import hashlib
import itertools
import json
import os
import random
import re
import resource
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

# ---------------------------------------------------------------- the stated limits (normative in Rev 3)
MAX_DEG = 6          # A3: a monomial above this degree, after resolution, refuses the constraint
MAX_CLOSURE = 256    # A3: more monomials than this in the resolution closure refuses the constraint
MAX_POLY = 256       # A3: a polynomial above this size at any step of expansion refuses the constraint
MAX_PAIRS = 64       # F4, F5, F10 are omitted for a constraint with more pairs
MAX_WRITTEN = None   # A1: None means no written-pair cap. Section 5 measures 4 against None
FORMS_LIMIT = 32     # a written factor with more resolved forms keeps its splits and loses only the written pair
RLIMIT = 2000000
GUARD_S = 5
MONO = "sym"         # "sym": one free symbol per monomial. "uf": nested mul##nl application (Rev 2)
SYM = "mul##nl"
FIRST_ONLY = False   # section 3 control only: Rev 2's reading, one rule per atom in conjunct order
NESTED = False       # section 5 only: Rev 2's nested sums and parens round a comparison in a fact

ARITH = {"+", "-", "*", "/", "mod"}
REL = {"<", "<=", ">", ">=", "=", "!="}
INT = re.compile(r"-?\d+$")
SOLVER_CALLS = {"z3": 0, "fixpoint": 0}


class Refused(Exception):
    def __init__(self, construct, why):
        Exception.__init__(self, f"{construct}: {why}")
        self.construct, self.why = construct, why


class Unreadable(Exception):
    pass


def parse(s):
    toks = re.findall(r"[()]|[^\s()]+", s)

    def rd(i):
        if toks[i] == "(":
            out, i = [], i + 1
            while toks[i] != ")":
                x, i = rd(i)
                out.append(x)
            return out, i + 1
        return toks[i], i + 1
    return rd(0)[0]


def W(vs, hyps, goal):
    return ({v for v in vs.split()}, [parse(h) for h in hyps], parse(goal))


# ---------------------------------------------------------------- polynomials
def padd(a, b, s=1):
    r = dict(a)
    for k, v in b.items():
        r[k] = r.get(k, 0) + s * v
    return {k: v for k, v in r.items() if v}


def pmul(a, b):
    if len(a) * len(b) > MAX_POLY:
        raise Refused("nonlinear:*", f"expansion over {MAX_POLY} monomials")
    r = {}
    for k1, v1 in a.items():
        for k2, v2 in b.items():
            k = tuple(sorted(k1 + k2))
            r[k] = r.get(k, 0) + v1 * v2
    return {k: v for k, v in r.items() if v}


def pkey(p):
    return "+".join(f"{c}*{'.'.join(m)}" for m, c in sorted(p.items())) or "0"


def is_const(p):
    return all(not m for m in p)


def const_of(p):
    return p.get((), 0)


def deg(p):
    return max((len(m) for m in p), default=0)


def rel_const(o, c):
    return {"<": c < 0, "<=": c <= 0, ">": c > 0, ">=": c >= 0, "=": c == 0, "!=": c != 0}[o]


# ---------------------------------------------------------------- values for validation
class FMap:
    """A finite map with a default: the validator's reading of an array."""

    def __init__(self, default, d=None):
        self.default = default
        self.d = {k: v for k, v in (d or {}).items() if v != default}

    def get(self, i):
        return self.d.get(i, self.default)

    def store(self, i, v):
        d = dict(self.d)
        d[i] = v
        return FMap(self.default, d)

    def __eq__(self, o):
        return isinstance(o, FMap) and self.default == o.default and self.d == o.d

    def __ne__(self, o):
        return not self == o

    def __hash__(self):
        return hash((repr(self.default), tuple(sorted((k, repr(v)) for k, v in self.d.items()))))

    def __repr__(self):
        return f"map(default={self.default!r}, {dict(sorted(self.d.items()))})"


class Token:
    """An opaque Str value: equality only."""

    def __init__(self, n):
        self.n = n

    def __eq__(self, o):
        return isinstance(o, Token) and self.n == o.n

    def __ne__(self, o):
        return not self == o

    def __hash__(self):
        return hash(self.n)

    def __repr__(self):
        return self.n


# ---------------------------------------------------------------- source evaluator, independent of the normal form
def ev_src(t, env, fns):
    if isinstance(t, str):
        if INT.match(t):
            return int(t)
        if t in env:
            return env[t]
        raise Unreadable("no value for " + t)
    op, *a = t
    if op == "if":
        return ev_src(a[1], env, fns) if ev_src(a[0], env, fns) else ev_src(a[2], env, fns)
    v = [ev_src(x, env, fns) for x in a]
    if op == "+": return sum(v)
    if op == "-": return v[0] - sum(v[1:]) if len(v) > 1 else -v[0]
    if op == "*":
        r = 1
        for x in v:
            r *= x
        return r
    if op == "/": return v[0] // v[1]
    if op == "mod": return v[0] % v[1]
    if op == "abs": return abs(v[0])
    if op == "max": return max(v)
    if op == "min": return min(v)
    if op == "<": return v[0] < v[1]
    if op == "<=": return v[0] <= v[1]
    if op == ">": return v[0] > v[1]
    if op == ">=": return v[0] >= v[1]
    if op == "=": return v[0] == v[1]
    if op == "!=": return v[0] != v[1]
    if op == "and": return all(v)
    if op == "or": return any(v)
    if op == "not": return not v[0]
    if op == "=>": return (not v[0]) or v[1]
    if op == "select": return v[0].get(v[1])
    if op == "store": return v[0].store(v[1], v[2])
    return fns(op, tuple(v))


# ---------------------------------------------------------------- the refusal scan, on the source, before expansion
def ground(t):
    if isinstance(t, str):
        return int(t) if INT.match(t) else None
    op, *a = t
    v = [ground(x) for x in a]
    if any(x is None for x in v) or op not in ARITH:
        return None
    if op in ("/", "mod") and v[1] <= 0:
        return None
    return ev_src(t, {}, None)


def refusal_scan(t):
    """A3/A4. Runs on the written term, so a cancellation cannot delete a refused term."""
    if isinstance(t, str):
        return
    op, *a = t
    if op in ("/", "mod"):
        k = ground(a[1])
        if k is None or k <= 0:
            raise Refused(f"nonlinear:{op}", f"divisor {a[1]} is not a positive ground constant")
    for x in a:
        refusal_scan(x)


class VC:
    """One constraint: atoms, normal form, rules, closure, facts."""

    def __init__(self, hyps, goal, sorts=None, ground_facts=True):
        self.atoms = {}
        self.sorts = sorts or {}
        self.hyps = []
        for h in hyps:
            self.flat(h)
        self.goal = goal
        for t in self.hyps + [goal]:
            refusal_scan(t)
        self.own = list(self.hyps)
        if ground_facts:
            self.hyps = self.hyps + self.ground_hyps()
        self.T, self.capped, self.closure_size, self.max_deg = 0, False, 0, 0
        self.rules = {}
        self.read_rules()

    def flat(self, h):
        if isinstance(h, list) and h[0] == "and":
            for x in h[1:]:
                self.flat(x)
        else:
            self.hyps.append(h)

    def ground_hyps(self):
        """The ground-fact families that the emitter adds: byte-range, measure-nonneg. They stay in the recheck."""
        out, seen = [], set()

        def add(t):
            k = json.dumps(t)
            if k not in seen:
                seen.add(k)
                out.append(t)

        def walk(t):
            if isinstance(t, str):
                return
            if t[0] == "select" and isinstance(t[1], str) and self.sorts.get(t[1]) == "bytes":
                add([">=", t, "0"])
                add(["<=", t, "255"])
            for x in t[1:]:
                walk(x)
        for t in self.hyps + [self.goal]:
            walk(t)
        for v, s in sorted(self.sorts.items()):
            if s == "bytes":
                add([">=", ["bytesLen", v], "0"])
            if s == "Str":
                add([">=", ["strLen", v], "0"])
        return out

    # ------------------------------------------------------------ normal form
    def poly(self, t):
        if isinstance(t, str):
            if INT.match(t):
                return {(): int(t)} if int(t) else {}
            self.atoms.setdefault(t, ("var", t))
            return {(t,): 1}
        op, *a = t
        if op == "+":
            r = {}
            for x in a:
                r = padd(r, self.poly(x))
            return r
        if op == "-":
            r = self.poly(a[0])
            if len(a) == 1:
                return padd({}, r, -1)
            for x in a[1:]:
                r = padd(r, self.poly(x), -1)
            return r
        if op == "*":
            r = {(): 1}
            for x in a:
                r = pmul(r, self.poly(x))
            return r
        if op == "/":
            return self.mkdiv(self.poly(a[0]), ground(a[1]))
        if op == "mod":
            return self.mkmod(self.poly(a[0]), ground(a[1]))
        if op == "if":
            return self.mkite(self.cnorm(a[0]), self.poly(a[1]), self.poly(a[2]))
        if op == "abs":
            x = self.poly(a[0])
            return self.mkite(("rel", "<", x), padd({}, x, -1), x)
        if op == "max":
            x, y = self.poly(a[0]), self.poly(a[1])
            return self.mkite(("rel", ">=", padd(x, y, -1)), x, y)
        if op == "min":
            x, y = self.poly(a[0]), self.poly(a[1])
            return self.mkite(("rel", "<=", padd(x, y, -1)), x, y)
        return self.mkuf(op, [self.poly(x) for x in a])

    def cnorm(self, t):
        op, *a = t
        if op in REL:
            return ("rel", op, padd(self.poly(a[0]), self.poly(a[1]), -1))
        return (op, [self.cnorm(x) for x in a])

    def ckey(self, c):
        if c[0] == "rel":
            return f"{c[1]}[{pkey(c[2])}]"
        return f"{c[0]}[{','.join(self.ckey(x) for x in c[1])}]"

    def mkdiv(self, f, k):
        if is_const(f):
            v = const_of(f) // k
            return {(): v} if v else {}
        key = f"div({pkey(f)},{k})"
        self.atoms.setdefault(key, ("div", f, k))
        return {(key,): 1}

    def mkmod(self, f, k):
        if is_const(f):
            v = const_of(f) % k
            return {(): v} if v else {}
        key = f"mod({pkey(f)},{k})"
        self.atoms.setdefault(key, ("mod", f, k))
        return {(key,): 1}

    def mkite(self, c, p, q):
        if pkey(p) == pkey(q):
            return p
        if c[0] == "rel" and is_const(c[2]):
            return p if rel_const(c[1], const_of(c[2])) else q
        key = f"ite({self.ckey(c)},{pkey(p)},{pkey(q)})"
        self.atoms.setdefault(key, ("ite", c, p, q))
        return {(key,): 1}

    def mkuf(self, op, args):
        key = f"{op}({','.join(pkey(x) for x in args)})"
        self.atoms.setdefault(key, ("uf", op, args))
        return {(key,): 1}

    # ------------------------------------------------------------ rules: an unordered set, read from every equation
    def single(self, p):
        if len(p) == 1:
            (m, c), = p.items()
            if c == 1 and len(m) == 1 and self.atoms[m[0]][0] in ("var", "uf"):
                return m[0]
        return None

    def contains(self, v, p):
        for m in p:
            for a in m:
                if a == v or self.atom_contains(v, a):
                    return True
        return False

    def atom_contains(self, v, a):
        d = self.atoms[a]
        if d[0] in ("div", "mod"):
            return self.contains(v, d[1])
        if d[0] == "uf":
            return any(self.contains(v, x) for x in d[2])
        return False    # an FQIte atom is opaque to the rules

    def read_rules(self):
        """Every top-level equation, in both directions where a side is one atom. No order is read."""
        for h in self.hyps:
            if not (isinstance(h, list) and h[0] == "="):
                continue
            l, r = self.poly(h[1]), self.poly(h[2])
            eq = padd(l, r, -1)
            for v, e in ((self.single(l), r), (self.single(r), l)):
                if v is None or self.contains(v, e):
                    continue
                if FIRST_ONLY and any(k[0] == v for k in self.rules):
                    continue
                self.rules[(v, pkey(e))] = (v, e, eq)

    def subst_atom(self, a, x, e):
        if a == x:
            return e
        d = self.atoms[a]
        if not self.atom_contains(x, a):
            return {(a,): 1}
        if d[0] == "div":
            return self.mkdiv(self.subst(d[1], x, e), d[2])
        if d[0] == "mod":
            return self.mkmod(self.subst(d[1], x, e), d[2])
        return self.mkuf(d[1], [self.subst(p, x, e) for p in d[2]])

    def subst(self, p, x, e):
        out = {}
        for m, c in p.items():
            t = {(): c}
            n = sum(1 for a in m if a == x)
            if n and (len(m) - n + n * deg(e)) > MAX_DEG:
                raise Refused("nonlinear:*", f"degree over {MAX_DEG} after resolution")
            if n and len(e) ** n > MAX_POLY:
                raise Refused("nonlinear:*", f"expansion over {MAX_POLY} monomials after resolution")
            for a in m:
                t = pmul(t, self.subst_atom(a, x, e))
            out = padd(out, t)
        return out

    def relevant_rules(self, p):
        return [r for k, r in sorted(self.rules.items(), key=lambda kv: kv[0]) if self.contains(r[0], p)]

    # ------------------------------------------------------------ occurrence collection
    def walk_terms(self, t, out):
        if isinstance(t, str):
            return
        op, *a = t
        if op in REL:
            for x in a:
                out["polys"].append(self.poly(x))
        if op == "*" and len(a) == 2:
            out["written"].append((self.poly(a[0]), self.poly(a[1])))
        for x in a:
            self.walk_terms(x, out)

    def inner_polys(self, a):
        d = self.atoms[a]
        if d[0] in ("div", "mod"):
            return [d[1]]
        if d[0] == "uf":
            return list(d[2])
        if d[0] == "ite":
            return [d[2], d[3]] + self.cond_polys(d[1])
        return []

    def cond_polys(self, c):
        if c[0] == "rel":
            return [c[2]]
        return [p for x in c[1] for p in self.cond_polys(x)]

    def monos_deep(self, polys):
        seen, stack = set(), list(polys)
        while stack:
            p = stack.pop()
            for m in p:
                if m not in seen:
                    seen.add(m)
                    for a in m:
                        stack.extend(self.inner_polys(a))
        return seen

    # ------------------------------------------------------------ closure and settled monomials
    def node_kind(self, m):
        return len(m) >= 2 or (len(m) == 1 and self.atoms[m[0]][0] != "var")

    def closure(self, seeds):
        """Every monomial that the rules reach. Whole or nothing: over a limit, the constraint refuses."""
        graph, stack = {}, [m for m in seeds if self.node_kind(m)]
        while stack:
            m = stack.pop()
            if m in graph:
                continue
            if len(m) > MAX_DEG:
                raise Refused("nonlinear:*", f"degree {len(m)} over {MAX_DEG} after resolution")
            graph[m] = []
            if len(graph) > MAX_CLOSURE:
                raise Refused("nonlinear:*", f"closure over {MAX_CLOSURE} monomials")
            for rule in self.relevant_rules({m: 1}):
                q = self.subst({m: 1}, rule[0], rule[1])
                graph[m].append((rule, q))
                for n in self.monos_deep([q]):
                    if self.node_kind(n) and n not in graph:
                        stack.append(n)
            for a in m:
                for n in self.monos_deep(self.inner_polys(a)):
                    if self.node_kind(n) and n not in graph:
                        stack.append(n)
        return graph

    @staticmethod
    def bottom_nodes(succ):
        """Nodes in a bottom strongly connected component of succ. Iterative Tarjan. Reads no name."""
        index, low, on, st, comp, n, cid = {}, {}, set(), [], {}, 0, 0
        for root in sorted(succ, key=repr):
            if root in index:
                continue
            work = [(root, iter(succ[root]))]
            index[root] = low[root] = n
            n += 1
            st.append(root)
            on.add(root)
            while work:
                v, it = work[-1]
                adv = False
                for w in it:
                    if w not in index:
                        index[w] = low[w] = n
                        n += 1
                        st.append(w)
                        on.add(w)
                        work.append((w, iter(succ[w])))
                        adv = True
                        break
                    if w in on:
                        low[v] = min(low[v], index[w])
                if adv:
                    continue
                work.pop()
                if work:
                    low[work[-1][0]] = min(low[work[-1][0]], low[v])
                if low[v] == index[v]:
                    while True:
                        w = st.pop()
                        on.discard(w)
                        comp[w] = cid
                        if w == v:
                            break
                    cid += 1
        leaves = {c for c in comp.values()}
        for v, ws in succ.items():
            for w in ws:
                if comp[w] != comp[v]:
                    leaves.discard(comp[v])
        return {v for v in succ if comp[v] in leaves}

    def settled(self, graph):
        nodes = [m for m in graph if len(m) >= 2]
        succ = {}
        for m in nodes:
            succ[m] = sorted({n for _, q in graph[m] for n in q if len(n) >= 2 and n in graph})
        bottom = self.bottom_nodes(succ)
        out = set()
        for m in bottom:
            # one monomial with a rule whose results all have degree 1 or less is fully resolved: it has no pair
            if graph[m] and not succ[m]:
                continue
            out.add(m)
        return out

    def forms(self, p):
        """Settled forms of a written factor, or None over the limit."""
        nodes, stack = {}, [p]
        keyed = {}
        while stack:
            x = stack.pop()
            k = pkey(x)
            if k in nodes:
                continue
            keyed[k] = x
            nodes[k] = []
            if len(nodes) > FORMS_LIMIT:
                return None
            for rule in self.relevant_rules(x):
                y = self.subst(x, rule[0], rule[1])
                nodes[k].append(pkey(y))
                stack.append(y)
        bottom = self.bottom_nodes({k: sorted(set(v)) for k, v in nodes.items()})
        return [keyed[k] for k in sorted(bottom)]

    # ------------------------------------------------------------ canonical relations
    @staticmethod
    def canon(o, p):
        if o == ">":
            o, p = "<", padd({}, p, -1)
        elif o == ">=":
            o, p = "<=", padd({}, p, -1)
        elif o in ("=", "!="):
            n = padd({}, p, -1)
            if pkey(n) < pkey(p):
                p = n
        return o, p

    def facts(self):
        coll = {"polys": [], "written": []}
        for h in self.hyps:
            self.walk_terms(h, coll)
        self.walk_terms(self.goal, coll)
        F = {}

        def rel(op, l, r):
            return (op, padd(l, r, -1))

        def add(fam, prem, con):
            ps = {}
            for o, p in prem:
                if is_const(p):
                    if not rel_const(o, const_of(p)):
                        return
                else:
                    o2, p2 = self.canon(o, p)
                    ps[(o2, pkey(p2))] = (o2, p2)
            if is_const(con[1]) and rel_const(con[0], const_of(con[1])):
                return
            c2 = self.canon(con[0], con[1])
            key = (tuple(sorted(ps)), c2[0], pkey(c2[1]))
            if key not in F:
                F[key] = (fam, [ps[k] for k in sorted(ps)], c2)

        seeds = self.monos_deep(coll["polys"])
        graph = self.closure(seeds)
        self.closure_size = len(graph)
        self.max_deg = max((len(m) for m in graph), default=0)
        # F9: one link for each rule at each monomial
        for m in sorted(graph):
            for rule, q in graph[m]:
                add("F9", [("=", rule[2])], rel("=", {m: 1}, q))
        settled = self.settled(graph)
        self.settled_count = len(settled)
        pairs = {}

        def addpair(a, b):
            if is_const(a) or is_const(b):
                return
            k1, k2 = pkey(a), pkey(b)
            if k1 > k2:
                a, b, k1, k2 = b, a, k2, k1
            pairs.setdefault((k1, k2), (a, b))

        for a, b in coll["written"]:
            fa, fb = self.forms(a), self.forms(b)
            if fa is None or fb is None:
                continue
            for x in fa:
                for y in fb:
                    if len(x) * len(y) > MAX_POLY:
                        continue
                    t = pmul(x, y)
                    if MAX_WRITTEN is None or len(t) <= MAX_WRITTEN:
                        addpair(x, y)
        todo = sorted(settled)
        done = set()
        while todo:
            m = todo.pop()
            if m in done:
                continue
            done.add(m)
            idx = range(len(m))
            for r in range(1, len(m)):
                for c in itertools.combinations(idx, r):
                    A = tuple(m[i] for i in c)
                    B = tuple(m[i] for i in idx if i not in c)
                    addpair({A: 1}, {B: 1})
                    if len(A) >= 2:
                        todo.append(A)
                    if len(B) >= 2:
                        todo.append(B)
        items = [pairs[k] for k in sorted(pairs)]
        self.T = len(items)
        zero, one = {}, {(): 1}
        # the literals of the constraint, for F11
        lits = set()
        allm = self.monos_deep(coll["polys"])
        polys = list(coll["polys"])
        for m in allm:
            for a in m:
                polys.extend(self.inner_polys(a))
        for p in polys:
            for m, c in p.items():
                lits.add(c)
        lits -= {0, 1}
        self.lits = sorted(lits)
        for a, b in items:
            t = pmul(a, b)
            for x, y in ((a, b), (b, a)):
                add("F1", [rel(">=", x, zero), rel(">=", y, zero)], rel(">=", t, zero))
                add("F1", [rel("<=", x, zero), rel(">=", y, zero)], rel("<=", t, zero))
                add("F2", [rel("=", x, zero)], rel("=", t, zero))
                add("F2", [rel("=", x, one)], rel("=", t, y))
                add("F3", [rel(">=", x, one), rel(">=", y, zero)], rel(">=", t, y))
                if len(x) == 1 and list(x.values())[0] == 1 and len(list(x)[0]) == 1:
                    for k in self.lits:
                        add("F11", [rel("=", x, {(): k})], rel("=", t, pmul({(): k}, y)))
            if pkey(a) == pkey(b):
                add("F8", [], rel(">=", t, zero))
        self.capped = len(items) > MAX_PAIRS
        for (a, b), (c, d) in ([] if self.capped else itertools.permutations(items, 2)):
            t1, t2 = pmul(a, b), pmul(c, d)
            for p, q, r, s in ((a, b, c, d), (a, b, d, c), (b, a, c, d), (b, a, d, c)):
                add("F4", [rel("<=", p, r), rel("<=", q, s), rel(">=", q, zero), rel(">=", r, zero)], rel("<=", t1, t2))
                add("F5", [rel("<", p, r), rel("<=", q, s), rel(">=", q, zero), rel(">=", r, zero)], rel("<=", padd(t1, q), t2))
                add("F10", [rel("=", p, r), rel("=", q, s)], rel("=", t1, t2))
        # literal bounds: top-level, closed over atom-to-atom rules, plus the bounds of a mod atom
        alias = {}
        for (v, _), (x, e, _) in sorted(self.rules.items()):
            s = self.single(e)
            if s is not None:
                alias.setdefault(x, set()).add(s)

        def aliases(a):
            seen, st = {a}, [a]
            while st:
                for b in alias.get(st.pop(), ()):
                    if b not in seen:
                        seen.add(b)
                        st.append(b)
            return seen
        ub, lb = {}, {}
        FLIP = {"<": ">", "<=": ">=", ">": "<", ">=": "<=", "=": "="}
        for h in self.hyps:
            if isinstance(h, list) and h[0] in FLIP:
                l, r = self.poly(h[1]), self.poly(h[2])
                for x, y, o in ((l, r, h[0]), (r, l, FLIP[h[0]])):
                    if len(x) == 1 and is_const(y) and list(x.values())[0] == 1 and len(list(x)[0]) == 1:
                        at, k = list(x)[0][0], const_of(y)
                        for b in aliases(at):
                            if o in ("<=", "="):
                                ub.setdefault(b, set()).add(k)
                            elif o == "<":
                                ub.setdefault(b, set()).add(k - 1)
                            if o in (">=", "="):
                                lb.setdefault(b, set()).add(k)
                            elif o == ">":
                                lb.setdefault(b, set()).add(k + 1)
        for a, d in self.atoms.items():
            if d[0] == "mod":
                ub.setdefault(a, set()).add(d[2] - 1)
                lb.setdefault(a, set()).add(0)
        for a, b in items:
            for x, y in ((a, b), (b, a)):
                if len(x) == 1 and list(x.values())[0] == 1 and len(list(x)[0]) == 1:
                    at = list(x)[0][0]
                    t = pmul(a, b)
                    for K in sorted(ub.get(at, ())):
                        kp = {(): K} if K else {}
                        add("F7b", [rel("<=", x, kp), rel(">=", y, zero)], rel("<=", t, pmul({(): K}, y) if K else {}))
                    for K in sorted(lb.get(at, ())):
                        if K >= 0:
                            kp = {(): K} if K else {}
                            add("F7b", [rel(">=", x, kp), rel(">=", y, zero)], rel(">=", t, pmul({(): K}, y) if K else {}))
        for m in sorted(done):
            if all(a in ub for a in m):
                for combo in itertools.product(*[sorted(ub[a]) for a in m]):
                    if all(k >= 0 for k in combo):
                        v = 1
                        for k in combo:
                            v *= k
                        prem = []
                        for a, k in zip(m, combo):
                            prem += [rel(">=", {(a,): 1}, zero), rel("<=", {(a,): 1}, {(): k} if k else {})]
                        add("F7", prem, rel("<=", {m: 1}, {(): v} if v else {}))
        out = list(F.values())
        return out

    # ------------------------------------------------------------ printing. Sums are flat
    def ppoly(self, p, mode):
        parts = []
        for m, c in sorted(p.items()):
            if not m:
                parts.append(self.pnum(c, mode))
            elif c == 1:
                parts.append(self.pmono(m, mode))
            elif mode == "fq":
                parts.append(f"{self.pnum(c, mode)} * {self.pmono(m, mode)}")
            else:
                parts.append(f"(* {self.pnum(c, mode)} {self.pmono(m, mode)})")
        if not parts:
            return "0"
        if len(parts) == 1:
            return parts[0]
        if NESTED and mode == "fq":
            r = parts[0]
            for x in parts[1:]:
                r = f"({r} + {x})"
            return r
        return " + ".join(parts) if mode == "fq" else "(+ " + " ".join(parts) + ")"

    def pnum(self, c, mode):
        if c >= 0:
            return str(c)
        return f"(0 - {-c})" if mode == "fq" else f"(- {-c})"

    def mono_key(self, m):
        return ".".join(m)

    def pmono(self, m, mode):
        if len(m) == 1:
            return self.patom(m[0], mode)
        if mode == "nat":
            r = self.patom(m[0], mode)
            for a in m[1:]:
                r = f"(* {r} {self.patom(a, mode)})"
            return r
        return "<<" + self.mono_key(m) + ">>"

    def wrap(self, p, mode):
        s = self.ppoly(p, mode)
        return f"({s})" if (mode == "fq" and (len(p) > 1 or (len(p) == 1 and list(p.values())[0] not in (1,)))) else s

    def patom(self, a, mode):
        d = self.atoms[a]
        if d[0] == "var":
            return d[1]
        if d[0] == "div":
            return f"({self.wrap(d[1], mode)} / {d[2]})" if mode == "fq" else f"(div {self.ppoly(d[1], mode)} {d[2]})"
        if d[0] == "mod":
            return f"({self.wrap(d[1], mode)} mod {d[2]})" if mode == "fq" else f"(mod {self.ppoly(d[1], mode)} {d[2]})"
        if d[0] == "ite":
            if mode == "fq":
                return f"(if {self.pcond(d[1], mode)} then {self.ppoly(d[2], mode)} else {self.ppoly(d[3], mode)})"
            return f"(ite {self.pcond(d[1], mode)} {self.ppoly(d[2], mode)} {self.ppoly(d[3], mode)})"
        if mode == "fq":
            op = {"select": "Map_select", "store": "Map_store"}.get(d[1], d[1])
            return "(" + op + " " + " ".join(self.wrap(x, mode) for x in d[2]) + ")"
        return "(" + d[1] + " " + " ".join(self.ppoly(x, mode) for x in d[2]) + ")"

    def pcond(self, c, mode):
        if c[0] == "rel":
            return self.prel(c[1], c[2], mode, True)
        xs = [self.pcond(x, mode) for x in c[1]]
        if c[0] == "not":
            return f"(not {xs[0]})"
        if c[0] == "=>":
            return f"({xs[0]} => {xs[1]})" if mode == "fq" else f"(=> {xs[0]} {xs[1]})"
        o = {"and": "&&", "or": "||"}[c[0]]
        return "(" + f" {o} ".join(xs) + ")" if mode == "fq" else f"({c[0]} " + " ".join(xs) + ")"

    def prel(self, o, p, mode, parens=True):
        lhs, rhs = {}, {}
        for m, c in p.items():
            if c > 0:
                lhs[m] = c
            else:
                rhs[m] = -c
        if not lhs and not rhs:
            return "true" if rel_const(o, 0) else "false"
        L, R = self.ppoly(lhs, mode), self.ppoly(rhs, mode)
        if mode == "fq":
            s = f"{L} {o} {R}"
            return f"({s})" if parens else s
        if o == "!=":
            return f"(not (= {L} {R}))"
        return f"({o} {L} {R})"

    def pform(self, t, mode, parens=True):
        op, *a = t
        if op in REL:
            return self.prel(op, padd(self.poly(a[0]), self.poly(a[1]), -1), mode, parens)
        if op == "and":
            xs = []

            def go(n):
                if isinstance(n, list) and n[0] == "and":
                    for m in n[1:]:
                        go(m)
                else:
                    xs.append(self.pform(n, mode))
            go(t)
            xs = [x for x in xs if x != "true"]
            if not xs:
                return "true"
            if "false" in xs:
                return "false"
            return "(" + " && ".join(xs) + ")" if mode == "fq" else "(and " + " ".join(xs) + ")"
        if op == "or":
            xs = [self.pform(x, mode) for x in a]
            return "(" + " || ".join(xs) + ")" if mode == "fq" else "(or " + " ".join(xs) + ")"
        if op == "not":
            return f"(not {self.pform(a[0], mode)})"
        if op == "=>":
            x, y = self.pform(a[0], mode), self.pform(a[1], mode)
            return f"({x} => {y})" if mode == "fq" else f"(=> {x} {y})"
        raise ValueError(op)

    def pfact(self, f, mode):
        """A1: no parens round a comparison inside a fact."""
        _, ps, con = f
        c = self.prel(con[0], con[1], mode, NESTED)
        if not ps:
            return c if mode != "fq" else f"({c})"
        xs = [self.prel(o, p, mode, NESTED) for o, p in ps]
        if mode == "fq":
            return f"(({' && '.join(xs)}) => {c})"
        return f"(=> (and {' '.join(xs)}) {c})"

    # ------------------------------------------------------------ evaluation in exact integers
    def val_atom(self, a, env, fns):
        d = self.atoms[a]
        if d[0] == "var":
            if d[1] not in env:
                raise Unreadable("no value for " + d[1])
            return env[d[1]]
        if d[0] == "div":
            return self.val_poly(d[1], env, fns) // d[2]
        if d[0] == "mod":
            return self.val_poly(d[1], env, fns) % d[2]
        if d[0] == "ite":
            return self.val_poly(d[2], env, fns) if self.val_cond(d[1], env, fns) else self.val_poly(d[3], env, fns)
        args = [self.val_poly(x, env, fns) for x in d[2]]
        if d[1] == "select":
            return args[0].get(args[1])
        if d[1] == "store":
            return args[0].store(args[1], args[2])
        return fns(d[1], tuple(args))

    def val_poly(self, p, env, fns):
        if len(p) == 1:
            (m, c), = p.items()
            if c == 1 and len(m) == 1:
                return self.val_atom(m[0], env, fns)
        tot = 0
        for m, c in p.items():
            v = c
            for a in m:
                v = v * self.val_atom(a, env, fns)
            tot += v
        return tot

    def val_rel(self, o, p, env, fns):
        ms = list(p.items())
        if o in ("=", "!=") and len(ms) == 2 and all(len(m) == 1 and abs(c) == 1 for m, c in ms) and ms[0][1] == -ms[1][1]:
            x, y = self.val_atom(ms[0][0][0], env, fns), self.val_atom(ms[1][0][0], env, fns)
            return (x == y) if o == "=" else (x != y)
        return rel_const(o, self.val_poly(p, env, fns))

    def val_cond(self, c, env, fns):
        if c[0] == "rel":
            return self.val_rel(c[1], c[2], env, fns)
        xs = c[1]
        if c[0] == "and":
            return all(self.val_cond(x, env, fns) for x in xs)
        if c[0] == "or":
            return any(self.val_cond(x, env, fns) for x in xs)
        if c[0] == "not":
            return not self.val_cond(xs[0], env, fns)
        return (not self.val_cond(xs[0], env, fns)) or self.val_cond(xs[1], env, fns)

    def evalf(self, t, env, fns):
        op, *a = t
        if op in REL:
            return self.val_rel(op, padd(self.poly(a[0]), self.poly(a[1]), -1), env, fns)
        if op == "and":
            return all(self.evalf(x, env, fns) for x in a)
        if op == "or":
            return any(self.evalf(x, env, fns) for x in a)
        if op == "not":
            return not self.evalf(a[0], env, fns)
        if op == "=>":
            return (not self.evalf(a[0], env, fns)) or self.evalf(a[1], env, fns)
        raise ValueError(op)

    def eval_fact(self, f, env, fns):
        _, ps, con = f
        for o, p in ps:
            if not self.val_rel(o, p, env, fns):
                return None
        return self.val_rel(con[0], con[1], env, fns)

    # ------------------------------------------------------------ a name-free structure of a fact, for the invariance test
    def s_poly(self, p, ren):
        return frozenset((c, tuple(sorted((self.s_atom(a, ren) for a in m), key=repr))) for m, c in p.items())

    def s_atom(self, a, ren):
        d = self.atoms[a]
        if d[0] == "var":
            return ("v", ren.get(d[1], d[1]))
        if d[0] in ("div", "mod"):
            return (d[0], self.s_poly(d[1], ren), d[2])
        if d[0] == "uf":
            return ("f", d[1], tuple(self.s_poly(x, ren) for x in d[2]))
        return ("i", self.s_cond(d[1], ren), self.s_poly(d[2], ren), self.s_poly(d[3], ren))

    def s_cond(self, c, ren):
        if c[0] == "rel":
            return self.s_rel(c[1], c[2], ren)
        return (c[0], tuple(self.s_cond(x, ren) for x in c[1]))

    def s_rel(self, o, p, ren):
        if o == ">":
            o, p = "<", padd({}, p, -1)
        elif o == ">=":
            o, p = "<=", padd({}, p, -1)
        if o in ("=", "!="):
            return (o, frozenset({self.s_poly(p, ren), self.s_poly(padd({}, p, -1), ren)}))
        return (o, self.s_poly(p, ren))

    def s_fact(self, f, ren):
        _, ps, con = f
        return (frozenset(self.s_rel(o, p, ren) for o, p in ps), self.s_rel(con[0], con[1], ren))


# ---------------------------------------------------------------- back ends
def smt_sort(s):
    return {"bytes": "(Array Int Int)", "intmap": "(Array Int Int)", "strmap": "(Array Int Str)", "Str": "Str", "Int": "Int"}[s]


def fq_sort(s):
    return {"bytes": "(Map_t int int)", "intmap": "(Map_t int int)", "strmap": "(Map_t int Str)", "Str": "Str", "Int": "int"}[s]


def free_fns(vc):
    """Function name to argument sort. bytesLen, strLen and any other free function."""
    out = {}
    for d in vc.atoms.values():
        if d[0] == "uf" and d[1] not in ("select", "store"):
            out[d[1]] = d[2]
    return out


def fn_arg_sort(op):
    return "Str" if op == "strLen" else "bytes"


def decls_smt(vc, vs):
    out = []
    if any(s in ("Str", "strmap") for s in vc.sorts.values()):
        out.append("(declare-sort Str 0)")
    for v in sorted(vs):
        out.append(f"(declare-const {v} {smt_sort(vc.sorts.get(v, 'Int'))})")
    for u in sorted(free_fns(vc)):
        out.append(f"(declare-fun {u} ({smt_sort(fn_arg_sort(u))}) Int)")
    return out


MONO_PAT = re.compile(r"<<(.*?)>>")


def monos_in(texts):
    keys = set()
    for t in texts:
        keys |= set(MONO_PAT.findall(t))
    return sorted(keys)


def build_smt(vs, hyps, goal, sorts=None):
    vc = VC(hyps, goal, sorts)
    fx = vc.facts()
    facts = sorted(vc.pfact(f, "smt") for f in fx)
    body = [f"(assert {x})" for x in facts]
    body += [f"(assert {vc.pform(h, 'smt')})" for h in vc.hyps]
    body.append(f"(assert (not {vc.pform(goal, 'smt')}))")
    keys = monos_in(body)
    ids = {k: f"mnl_{i}" for i, k in enumerate(keys)}
    head = decls_smt(vc, vs)
    if MONO == "uf":
        head.append("(declare-fun mulnl (Int Int) Int)")
        rep = {k: uf_term_smt(vc, k) for k in keys}
    else:
        head += [f"(declare-const {ids[k]} Int)" for k in keys]
        rep = ids
    txt = "\n".join(head + body + ["(check-sat)"]) + "\n"
    txt = MONO_PAT.sub(lambda m: rep[m.group(1)], txt)
    return txt, vc, fx


def uf_term_smt(vc, key):
    ats = key.split(".") if key not in vc.atoms else [key]
    ats = split_mono(vc, key)
    r = vc.patom(ats[0], "smt")
    for a in ats[1:]:
        r = f"(mulnl {r} {vc.patom(a, 'smt')})"
    return MONO_PAT.sub(lambda m: uf_term_smt(vc, m.group(1)), r)


def split_mono(vc, key):
    """Recover the atoms of a monomial key by the longest known atom at each dot."""
    out, rest = [], key
    while rest:
        best = None
        for a in vc.atoms:
            if rest == a or rest.startswith(a + "."):
                if best is None or len(a) > len(best):
                    best = a
        if best is None:
            raise ValueError(key)
        out.append(best)
        rest = rest[len(best) + 1:]
    return out


def build_fq(vs, hyps, goal, sorts=None, env_hyps=()):
    """env_hyps are printed as binder refinements, the rest in the lhs. Facts and monomial binders have a fixed order."""
    vc = VC(hyps, goal, sorts)
    fx = vc.facts()
    facts = sorted(vc.pfact(f, "fq") for f in fx)
    envh = [json.dumps(h) for h in env_hyps]
    hs = [vc.pform(h, "fq") for h in vc.hyps if json.dumps(h) not in envh]
    eh = [vc.pform(h, "fq") for h in env_hyps]
    rhs = vc.pform(goal, "fq")
    lhs = facts + hs
    keys = monos_in(lhs + eh + [rhs])
    lines = []
    if any("strLen" == u for u in free_fns(vc)):
        lines.append("constant strLen : (func(0, [Str; int]))")
    if any("bytesLen" == u for u in free_fns(vc)):
        lines.append("constant bytesLen : (func(0, [(Map_t int int); int]))")
    bs = sorted(vs)
    bind = []
    for v in bs:
        bind.append((v, f"{{ v : {fq_sort(vc.sorts.get(v, 'Int'))} | true }}"))
    ids = {}
    if MONO == "uf":
        lines.append(f"constant {SYM} : (func(0, [int; int; int]))")
        # one binder for each prefix of each monomial
        allk = {}
        for k in keys:
            ats = split_mono(vc, k)
            for i in range(2, len(ats) + 1):
                allk[".".join(ats[:i])] = ats[:i]
        order = sorted(allk, key=lambda k: (len(allk[k]), k))
        for j, k in enumerate(order):
            ids[k] = f"m##{j}"
        for k in order:
            ats = allk[k]
            left = vc.patom(ats[0], "fq") if len(ats) == 2 else ids[".".join(ats[:-1])]
            bind.append((ids[k], f"{{ v : int | v = ({SYM} {left} {vc.patom(ats[-1], 'fq')}) }}"))
    else:
        for j, k in enumerate(keys):
            ids[k] = f"mul##{j}"
            bind.append((ids[k], "{ v : int | true }"))
    for j, e in enumerate(eh):
        bind.append((f"h##{j}", f"{{ v : int | {e} }}"))
    for i, (n, r) in enumerate(bind):
        lines.append(f"bind {i} {n} : {r}")
    lines += ["constraint:", f"  env [{'; '.join(str(i) for i in range(len(bind)))}]",
              f"  lhs {{ VV : int | {' && '.join(lhs) or 'true'} }}", f"  rhs {{ VV : int | {rhs} }}", "  id 0", "  tag [0]"]
    txt = "\n".join(lines) + "\n"
    # binder text and clause text can both hold a monomial placeholder
    for _ in range(4):
        txt = MONO_PAT.sub(lambda m: ids[m.group(1)], txt)
    vc.rhs_true = rhs == "true"
    vc.fact_block = "\n".join(facts)
    return txt, vc, fx


def z3_run(text, tmo, extra=()):
    SOLVER_CALLS["z3"] += 1
    with tempfile.NamedTemporaryFile("w", suffix=".smt2", delete=False) as f:
        f.write(text)
    t = time.time()
    try:
        p = subprocess.run(["z3", f"-T:{tmo}", *extra, f.name], capture_output=True, text=True, timeout=tmo + 20)
        out = p.stdout
    except subprocess.TimeoutExpired:
        out = "guard-timeout\n"
    os.unlink(f.name)
    return out, round(time.time() - t, 3)


def fixpoint(text, tmo):
    """Result and CPU seconds, fixpoint plus its z3 child."""
    SOLVER_CALLS["fixpoint"] += 1
    d = tempfile.mkdtemp()
    fn = os.path.join(d, "w.fq")
    with open(fn, "w") as f:
        f.write(text)
    r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    try:
        p = subprocess.run(["fixpoint", fn], capture_output=True, text=True, timeout=tmo, cwd=d)
        o = re.sub(r"\x1b\[[0-9;]*m", "", p.stdout + p.stderr)
        r = "SAFE" if re.search(r"\bSafe\b", o) else "UNSAFE" if re.search(r"\bUnsafe\b", o) else "ERR " + " ".join(o.split())[-300:]
    except subprocess.TimeoutExpired:
        r = f"none in {tmo}s"
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    shutil.rmtree(d, ignore_errors=True)
    return r, round(r1.ru_utime + r1.ru_stime - r0.ru_utime - r0.ru_stime, 3)


# ---------------------------------------------------------------- reading a real z3 model
def read_sexprs(s):
    """Top-level forms of z3's stdout. Strings are kept as one token."""
    s = re.sub(r";[^\n]*", "", s)
    toks = re.findall(r'"(?:[^"]|"")*"|\|[^|]*\||[()]|[^\s()]+', s)
    out, stack = [], []
    for t in toks:
        if t == "(":
            stack.append([])
        elif t == ")":
            if not stack:
                raise Unreadable("unbalanced")
            x = stack.pop()
            (stack[-1] if stack else out).append(x)
        else:
            (stack[-1] if stack else out).append(t)
    if stack:
        raise Unreadable("unbalanced")
    return out


def is_token(x):
    return isinstance(x, str) and "!val!" in x


def read_value(x, lets, model):
    if isinstance(x, str):
        if x in lets:
            return lets[x]
        if INT.match(x):
            return int(x)
        if is_token(x):
            return Token(x)
        raise Unreadable("value " + x)
    if not x:
        raise Unreadable("empty")
    h = x[0]
    if h == "-" and len(x) == 2:
        return -read_value(x[1], lets, model)
    if isinstance(h, list) and h and h[0] == "as" and h[1] == "const":
        return FMap(read_value(x[1], lets, model))
    if h == "store":
        return read_value(x[1], lets, model).store(read_value(x[2], lets, model), read_value(x[3], lets, model))
    if h == "let":
        l2 = dict(lets)
        for n, v in x[1]:
            l2[n] = read_value(v, lets, model)
        return read_value(x[2], l2, model)
    if h == "lambda":
        return read_fun(x[1][0][0], x[2], lets, model)
    if h == "_" and x[1] == "as-array":
        if x[2] not in model:
            raise Unreadable("as-array " + x[2])
        p, body = model[x[2]]
        return read_fun(p, body, lets, model)
    raise Unreadable("value " + json.dumps(x)[:80])


def read_fun(param, body, lets, model):
    pts = set()

    def scan(b):
        if isinstance(b, list):
            if len(b) == 3 and b[0] == "=" and param in b[1:]:
                o = b[1] if b[2] == param else b[2]
                pts.add(read_value(o, lets, model))
            for y in b:
                scan(y)
    scan(body)

    def ap(b, v, ls):
        if isinstance(b, str):
            if b == param:
                return v
            if b in ls:
                return ls[b]
            if b == "true":
                return True
            if b == "false":
                return False
            return read_value(b, ls, model)
        h = b[0]
        if h == "ite":
            return ap(b[2], v, ls) if ap(b[1], v, ls) else ap(b[3], v, ls)
        if h == "=":
            return ap(b[1], v, ls) == ap(b[2], v, ls)
        if h == "and":
            return all(ap(y, v, ls) for y in b[1:])
        if h == "or":
            return any(ap(y, v, ls) for y in b[1:])
        if h == "not":
            return not ap(b[1], v, ls)
        if h == "let":
            l2 = dict(ls)
            for n, y in b[1]:
                l2[n] = ap(y, v, ls)
            return ap(b[2], v, l2)
        return read_value(b, ls, model)
    far = max([abs(p) for p in pts if isinstance(p, int)], default=0) + 1000003
    return FMap(ap(body, far, lets), {p: ap(body, p, lets) for p in pts})


def native_query(vs, vc, goal, ground=True, rlimit=RLIMIT, get=True):
    hs = vc.hyps if ground else vc.own
    body = [f"(assert {vc.pform(h, 'nat')})" for h in hs]
    body.append(f"(assert (not {vc.pform(goal, 'nat')}))")
    head = decls_smt(vc, vs)
    if rlimit:
        head.insert(0, f"(set-option :rlimit {rlimit})")
    vals = sorted(vs)
    apps = sorted(a for a, d in vc.atoms.items() if d[0] == "uf" and d[1] not in ("select", "store"))
    terms = vals + [vc.patom(a, "nat") for a in apps]
    tail = ["(check-sat)"]
    if get:
        tail += [f"(get-value ({' '.join(terms)}))", "(get-model)"]
    tail.append("(get-info :all-statistics)")
    return "\n".join(head + body + tail) + "\n", vals, apps


def recheck(vs, hyps, goal, sorts=None, rlimit=RLIMIT, ground_facts=True):
    """A4. The native query, then validation of the model from z3's real get-value output.
    Returns (answer, wall, rlimit-count, model state, details)."""
    vc = VC(hyps, goal, sorts, ground_facts=ground_facts)
    # intern every atom before the declarations are printed
    for h in vc.hyps:
        vc.pform(h, "nat")
    vc.pform(goal, "nat")
    txt, vals, apps = native_query(vs, vc, goal, rlimit=rlimit)
    out, t = z3_run(txt, GUARD_S)
    first = out.strip().split("\n")[0] if out.strip() else "empty"
    rl = re.search(r":rlimit-count\s+(\d+)", out)
    rl = int(rl.group(1)) if rl else None
    if first != "sat":
        return first, t, rl, None, None
    det = {"raw": None}
    try:
        forms = read_sexprs(out[out.index("sat") + 3:])
        gv = forms[0]
        det["raw"] = " ".join(json.dumps(x, separators=(" ", " ")).replace('"', "").replace("[", "(").replace("]", ")") for x in gv)
        model = {}
        for fm in forms[1:]:
            if isinstance(fm, list):
                defs = fm[1:] if fm and fm[0] == "model" else fm
                for df in defs:
                    if isinstance(df, list) and len(df) == 5 and df[0] == "define-fun" and len(df[2]) == 1:
                        model[df[1]] = (df[2][0][0], df[4])
        if len(gv) != len(vals) + len(apps):
            raise Unreadable("get-value length")
        env = {}
        for v, row in zip(vals, gv):
            env[v] = read_value(row[1], {}, model)
        appv = [read_value(row[1], {}, model) for row in gv[len(vals):]]
    except (Unreadable, ValueError, IndexError) as e:
        return "sat", t, rl, "unreadable: " + str(e)[:80], det
    state, why = validate(vc, hyps, goal, env, apps, appv)
    det.update(env=env, apps=apps, appv=appv, vc=vc, hyps=hyps, why=why)
    return "sat", t, rl, state, det


def validate(vc, hyps, goal, env, apps, appv):
    """Both evaluators must agree. Function consistency: equal arguments, equal results."""
    table = {}
    try:
        def probe(op, args):
            raise Unreadable("function order")
        # a function application can hold another: evaluate in rounds
        pending = list(zip(apps, appv))
        for _ in range(len(pending) + 1):
            rest = []
            for a, v in pending:
                d = vc.atoms[a]
                try:
                    args = tuple(vc.val_poly(x, env, lambda o, y: lookup(table, o, y)) for x in d[2])
                except Unreadable:
                    rest.append((a, v))
                    continue
                k = (d[1], args)
                if k in table and table[k] != v:
                    return "MODEL FAILS", "function consistency"
                table[k] = v
            pending = rest
            if not pending:
                break
        if pending:
            return "unreadable: function argument", None
        fns = lambda o, y: lookup(table, o, y)
        for h in vc.hyps:
            if not vc.evalf(h, env, fns):
                return "MODEL FAILS", "hypothesis " + json.dumps(h)[:100]
        if vc.evalf(goal, env, fns):
            return "MODEL FAILS", "goal holds"
        # the second evaluator reads the source term, not the normal form
        for h in vc.hyps:
            if not ev_src(h, env, fns):
                return "MODEL FAILS", "source hypothesis " + json.dumps(h)[:100]
        if ev_src(goal, env, fns):
            return "MODEL FAILS", "source goal holds"
    except (Unreadable, TypeError, AttributeError) as e:
        return "unreadable: " + str(e)[:80], None
    return "validated", None


def lookup(table, op, args):
    k = (op, args)
    if k not in table:
        raise Unreadable(f"no value for {op}{args}")
    return table[k]


# ---------------------------------------------------------------- generator check
def hashed_fn(salt):
    def f(op, args):
        h = hashlib.sha256(repr((salt, op, args)).encode()).digest()
        return h[0] % 11 - 4
    return f


def random_env(vc, vs, rnd, pool):
    env = {}
    for v in vs:
        s = vc.sorts.get(v, "Int")
        if s == "Int":
            env[v] = rnd.choice(pool)
        elif s == "Str" :
            env[v] = Token(f"Str!val!{rnd.randint(0, 2)}")
        elif s == "strmap":
            env[v] = FMap(Token("Str!val!0"), {rnd.randint(-2, 3): Token(f"Str!val!{rnd.randint(0, 2)}")})
        else:
            env[v] = FMap(rnd.randint(0, 255), {rnd.randint(-2, 3): rnd.randint(0, 255)})
    return env


def gen_check(vs, hyps, goal, sorts=None, samples=120):
    vc = VC(hyps, goal, sorts)
    fx = vc.facts()
    rnd = random.Random(13)
    bad, fired, nfbad, nfn = 0, 0, 0, 0
    pool = list(range(-4, 7)) + [2**31, -(2**31), 2**63, 65535]
    for i in range(samples):
        env = random_env(vc, vs, rnd, pool)
        fns = hashed_fn(i)
        for f in fx:
            r = vc.eval_fact(f, env, fns)
            if r is not None:
                fired += 1
                if not r:
                    bad += 1
        for t in vc.hyps + [goal]:
            nfn += 1
            if bool(vc.evalf(t, env, fns)) != bool(ev_src(t, env, fns)):
                nfbad += 1
    return len(fx), bad, fired, nfn, nfbad


# ---------------------------------------------------------------- witnesses
BASE = ["(>= y 0)", "(< y h)", "(>= x 0)", "(< x w)"]
B3 = ["(>= c 0)", "(< c ch)"]
YB = ["(>= w 1)", "(>= h 1)", "(= cw (/ (+ w 1) 2))", "(= ch (/ (+ h 1) 2))"]
NFR = "(= n (+ (* w h) (* 2 (* cw ch))))"
PL = ["(>= w 1)", "(>= h 1)", "(>= p 0)", "(<= p 2)", "(>= pw 1)", "(>= ph 1)",
      "(=> (= p 0) (= pw w))", "(=> (> p 0) (= pw (/ (+ w 1) 2)))", "(=> (= p 0) (= ph h))", "(=> (> p 0) (= ph (/ (+ h 1) 2)))"]
CUR = ["(>= y 0)", "(>= x 0)"]
LET = ["(= rowb (* w c))", "(= st (+ rowb pad))", "(= luma (* w h))", "(= cw (/ (+ w 1) 2))", "(= ch (/ (+ h 1) 2))", "(= chroma (* cw ch))",
       "(= frame (+ luma (* 2 chroma)))", "(= src (+ (* y st) (* x c)))", "(= dst (+ (* y w) x))",
       "(= v (+ luma (+ chroma (+ (* (/ y 2) cw) (/ x 2)))))", "(= total (* h st))"]
PB = ["(>= w 1)", "(>= h 1)", "(>= c 1)", "(>= pad 0)", "(>= y 0)", "(<= y h)", "(>= x 0)", "(< x w)"]
PV = "w h c pad y x rowb st luma cw ch chroma frame src dst v total"

# group, name, vars, hyps, goal, truth, sorts
TBL = []


def T(group, name, vs, hyps, goal, truth=True, sorts=None):
    TBL.append(dict(group=group, name=name, w=W(vs, hyps, goal), truth=truth, sorts=sorts))


# ---- W: Rev 1 true
T("W", "W1 commute w*h = h*w", "w h r", ["(= r (* h w))"], "(= r (* w h))")
T("W", "W2 buffer len w*h*3", "w h r", ["(>= w 0)", "(>= h 0)", "(= r (* (* w h) 3))"], "(and (>= r 0) (= r (* 3 (* h w))))")
T("W", "W3 crux y*w+x < w*h", "w h y x r", BASE + ["(= r (+ (* y w) x))"], "(and (>= r 0) (< r (* w h)))")
T("W", "W4 stride", "w h y x c st r", BASE + ["(>= st (* 3 w))", "(>= c 0)", "(< c 3)", "(= r (+ (+ (* y st) (* 3 x)) c))"], "(and (>= r 0) (< r (* h st)))")
T("W", "W5 channels var", "w h y x c ch p r", BASE + ["(>= c 0)", "(< c ch)", "(= p (+ (* y w) x))", "(= r (+ (* p ch) c))"], "(and (>= r 0) (< r (* (* w h) ch)))")
T("W", "W5b channels unnamed", "w h y x c ch r", BASE + ["(>= c 0)", "(< c ch)", "(= r (+ (* (+ (* y w) x) ch) c))"], "(and (>= r 0) (< r (* (* w h) ch)))")
T("W", "W6 crop size", "w h ox oy cw ch", ["(>= ox 0)", "(>= oy 0)", "(>= cw 0)", "(>= ch 0)", "(<= (+ ox cw) w)", "(<= (+ oy ch) h)"], "(<= (* cw ch) (* w h))")
T("W", "W7 crop offset", "w h ox oy cw ch y x r", ["(>= ox 0)", "(>= oy 0)", "(>= y 0)", "(< y ch)", "(>= x 0)", "(< x cw)", "(<= (+ ox cw) w)", "(<= (+ oy ch) h)", "(= r (+ (* (+ y oy) w) (+ x ox)))"], "(and (>= r 0) (< r (* w h)))")
T("W", "W8 chroma offset", "w h cy cx r", ["(>= w 1)", "(>= h 1)", "(>= cy 0)", "(< cy (/ (+ h 1) 2))", "(>= cx 0)", "(< cx (/ (+ w 1) 2))", "(= r (+ (* cy (/ (+ w 1) 2)) cx))"], "(and (>= r 0) (< r (* (/ (+ w 1) 2) (/ (+ h 1) 2))))")
T("W", "W9 v plane in frame", "w h cy cx cw ch f r", ["(>= w 1)", "(>= h 1)", "(= cw (/ (+ w 1) 2))", "(= ch (/ (+ h 1) 2))", "(>= cy 0)", "(< cy ch)", "(>= cx 0)", "(< cx cw)", "(= f (+ (* w h) (* 2 (* cw ch))))", "(= r (+ (+ (* w h) (* cw ch)) (+ (* cy cw) cx)))"], "(and (>= r 0) (< r f))")
T("W", "W10 frame i of k", "f i k r", ["(>= f 0)", "(>= i 0)", "(< i k)", "(= r (* i f))"], "(and (>= r 0) (<= (+ r f) (* k f)))")
T("W", "W11 distribute", "y oy w r", ["(= r (+ (* y w) (* oy w)))"], "(= r (* (+ y oy) w))")
T("W", "W12 next row", "y w x off r", ["(= off (+ (* y w) x))", "(= x (- w 1))", "(= r (+ off 1))"], "(= r (* (+ y 1) w))")
T("W", "W13 byte index, bytes-length", "w h y x n", BASE + ["(= n (* (* w h) 3))"], "(and (>= (+ (* 3 (+ (* y w) x)) 2) 0) (< (+ (* 3 (+ (* y w) x)) 2) n))")
T("W", "W14 chroma covers (4cw*ch >= w*h)", "w h", ["(>= w 1)", "(>= h 1)"], "(>= (* 4 (* (/ (+ w 1) 2) (/ (+ h 1) 2))) (* w h))")
T("W", "W15 down2 (w/2)*(h/2) <= w*h", "w h", ["(>= w 0)", "(>= h 0)"], "(<= (* (/ w 2) (/ h 2)) (* w h))")
T("W", "W16 hflip offset", "w h y x r", BASE + ["(= r (+ (* y w) (- (- w 1) x)))"], "(and (>= r 0) (< r (* w h)))")
T("W", "W17 transpose offset", "w h y x r", BASE + ["(= r (+ (* x h) y))"], "(and (>= r 0) (< r (* w h)))")
T("W", "W18 alias of factor", "w h y x s r", BASE + ["(= s w)", "(= r (+ (* y s) x))"], "(and (>= r 0) (< r (* w h)))")
T("W", "W19 3-D offset z*h*w+y*w+x", "w h d z y x a n r", BASE + ["(>= z 0)", "(< z d)", "(= a (* h w))", "(= n (* d a))", "(= r (+ (+ (* z a) (* y w)) x))"], "(and (>= r 0) (< r n))")
T("W", "W20 int64 bound from ranges", "w h n", ["(>= w 0)", "(<= w 65535)", "(>= h 0)", "(<= h 65535)", "(= n (* (* w h) 3))"], "(and (>= n 0) (<= n 9223372036854775807))")
T("W", "W21 frame within file", "w h k i f hdr off len", ["(>= w 1)", "(>= h 1)", "(>= hdr 0)", "(>= i 0)", "(< i k)", "(= f (* (* w h) 3))", "(= off (+ hdr (* i f)))", "(<= (+ hdr (* k f)) len)"], "(and (>= off 0) (<= (+ off f) len))")
T("W", "W22 4-factor monotone", "a b c d p q s t", ["(>= a 0)", "(>= b 0)", "(>= c 0)", "(>= d 0)", "(<= a p)", "(<= b q)", "(<= c s)", "(<= d t)"], "(<= (* (* a b) (* c d)) (* (* p q) (* s t)))")
T("W", "W23 irrational: x*x != 2*y*y", "x y", ["(> x 0)", "(> y 0)"], "(not (= (* x x) (* 2 (* y y))))")
T("W", "W24 x*x+y*y=z*z parity", "x y z", ["(= (+ (* x x) (* y y)) (* z z))", "(> x 0)", "(> y 0)", "(> z 0)"], "(not (= (+ (* 4 (* x y)) 2) (* 4 (* z z))))")
T("W", "W25 AM-GM (a+b)^2>=4ab", "a b", [], "(>= (* (+ a b) (+ a b)) (* 4 (* a b)))")
T("W", "W26 two-image blit", "sw sh dw dh sx sy dx dy y x cw ch r1 r2", ["(>= sx 0)", "(>= sy 0)", "(>= dx 0)", "(>= dy 0)", "(>= y 0)", "(< y ch)", "(>= x 0)", "(< x cw)", "(<= (+ sx cw) sw)", "(<= (+ sy ch) sh)", "(<= (+ dx cw) dw)", "(<= (+ dy ch) dh)", "(= r1 (+ (* (+ y sy) sw) (+ x sx)))", "(= r2 (+ (* (+ y dy) dw) (+ x dx)))"], "(and (and (>= r1 0) (< r1 (* sw sh))) (and (>= r2 0) (< r2 (* dw dh))))")
# ---- P, R, Q
T("P", "P1 assoc", "w h c", [], "(= (* w (* h c)) (* (* w h) c))")
T("P", "P2 regroup value", "y w c r", ["(= r (* (* y w) c))"], "(= r (* y (* w c)))")
T("P", "P3 offset, h*(w*ch) buffer", "w h y x c ch r", BASE + B3 + ["(= r (+ (* (+ (* y w) x) ch) c))"], "(< r (* h (* w ch)))")
T("P", "P4 stride named, (w*h)*ch", "w h y x c ch st r", BASE + B3 + ["(= st (* w ch))", "(= r (+ (+ (* y st) (* x ch)) c))"], "(< r (* (* w h) ch))")
T("P", "P5 let constant channel", "w h ch n", ["(= ch 3)", "(= n (* (* w h) ch))"], "(= n (* 3 (* w h)))")
T("P", "P6 commuted aliases, any sign", "a b c d r", ["(= a d)", "(= b c)", "(= r (* a b))"], "(= r (* c d))")
T("P", "P7 cancel", "w h a b", ["(>= w 1)", "(= a (* w h))", "(= b (* h w))"], "(= (- a b) 0)")
T("R", "R1 rotate90 offset", "w h y x r", BASE + ["(= r (+ (* x h) (- (- h 1) y)))"], "(and (>= r 0) (< r (* w h)))")
T("R", "R2 BMP row stride", "w bpp st", ["(>= w 1)", "(>= bpp 1)", "(= st (* 4 (/ (+ (* w bpp) 31) 32)))"], "(>= (* 8 st) (* w bpp))")
T("R", "R3 four-plane total", "w h a n r y x p", BASE + ["(>= p 0)", "(< p 4)", "(= a (* w h))", "(= n (* 4 a))", "(= r (+ (* p a) (+ (* y w) x)))"], "(and (>= r 0) (< r n))")
T("R", "R4 bound from product pre", "w h n", ["(>= w 0)", "(>= h 0)", "(<= (* w h) 268435456)", "(= n (* 3 (* w h)))"], "(<= n 9223372036854775807)")
T("Q", "Q1 next-row regrouped", "y w c", ["(>= y 0)", "(>= w 0)", "(>= c 0)"], "(= (* (+ y 1) (* w c)) (+ (* y (* c w)) (* c w)))")
T("Q", "Q2 alias both factors", "w h s t", ["(= s h)", "(= t w)"], "(= (* s t) (* w h))")
T("Q", "Q3 equation written reversed", "w h y x c ch st r", BASE + B3 + ["(= (* w ch) st)", "(= r (+ (+ (* y st) (* x ch)) c))"], "(< r (* h st))")
T("Q", "Q4 buffer length as function", "w h y x b", BASE + ["(= (bytesLen b) (* w h))"], "(and (>= (+ (* y w) x) 0) (< (+ (* y w) x) (bytesLen b)))", True, {"b": "bytes"})
T("Q", "Q5 chained constant", "w h k ch n", ["(= k 3)", "(= ch k)", "(= n (* w (* h ch)))"], "(= n (* k (* h w)))")
T("Q", "Q6 stride = 3w, equality", "w h y x c st r", BASE + ["(>= c 0)", "(< c 3)", "(= st (* 3 w))", "(= r (+ (+ (* y st) (* 3 x)) c))"], "(< r (* h st))")
T("Q", "Q7 product as a bytes index", "w h y x b v", BASE + ["(= (bytesLen b) (* w h))", "(= v (select b (+ (* y w) x)))"], "(< (+ (* y w) x) (bytesLen b))", True, {"b": "bytes"})
T("Q", "Q8 alias by bounds", "a b c d", ["(<= a d)", "(<= d a)", "(<= b c)", "(<= c b)"], "(= (* a b) (* c d))")
T("Q", "Q9 equation in a disjunct", "a d b", ["(or (= a d) (= a (+ d 0)))"], "(= (* a b) (* d b))")
T("Q", "Q10 narrow row in wide stride", "w h y x st", BASE + ["(>= st w)"], "(< (+ (* y w) x) (* h st))")
T("Q", "Q11 padded stride, var channels", "w h y x c ch st r", BASE + B3 + ["(>= st (* w ch))", "(= r (+ (* (+ (* y w) x) ch) c))"], "(< r (* h st))")
T("Q", "Q12 stride offset, padded", "w h y x c ch st r", BASE + B3 + ["(>= st (* w ch))", "(= r (+ (+ (* y st) (* x ch)) c))"], "(< r (* h st))")
T("Q", "Q13 pad variable", "w h y x c ch pad st r", BASE + B3 + ["(>= pad 0)", "(= st (+ (* w ch) pad))", "(= r (+ (+ (* y st) (* x ch)) c))"], "(< r (* h st))")
T("Q", "Q14 row end in a stride", "w h y x st", ["(>= y 0)", "(< y h)", "(>= x 0)", "(< x w)", "(>= st w)", "(>= h 0)"], "(<= (+ (* y st) x) (* h st))")
T("Q", "Q15 total bound by a limit", "w h ch lim", ["(>= w 0)", "(>= h 0)", "(>= ch 0)", "(<= (* w h) lim)", "(<= ch 4)"], "(<= (* (* w h) ch) (* 4 lim))")
# ---- M, N false
T("M", "M1 x<=w (off by one)", "w h y x r", ["(>= y 0)", "(< y h)", "(>= x 0)", "(<= x w)", "(= r (+ (* y w) x))"], "(< r (* w h))", False)
T("M", "M2 y<=h", "w h y x r", ["(>= y 0)", "(<= y h)", "(>= x 0)", "(< x w)", "(= r (+ (* y w) x))"], "(< r (* w h))", False)
T("M", "M3 swapped stride y*h", "w h y x r", BASE + ["(= r (+ (* y h) x))"], "(< r (* w h))", False)
T("M", "M4 no lower bound", "w h y x r", ["(< y h)", "(>= x 0)", "(< x w)", "(= r (+ (* y w) x))"], "(>= r 0)", False)
T("M", "M5 negative h,w product", "w h", [], "(>= (* w h) 0)", False)
T("M", "M6 w*w = w*h", "w h r", ["(= r (* w w))"], "(= r (* w h))", False)
T("M", "M7 wrong chroma w/2", "w h cy cx r", ["(>= w 1)", "(>= h 1)", "(>= cy 0)", "(< cy (/ (+ h 1) 2))", "(>= cx 0)", "(< cx (/ (+ w 1) 2))", "(= r (+ (* cy (/ w 2)) cx))"], "(< r (* (/ w 2) (/ h 2)))", False)
T("M", "M8 blit with swapped widths", "sw sh dw dh sx sy dx dy y x cw ch r2", ["(>= sx 0)", "(>= sy 0)", "(>= dx 0)", "(>= dy 0)", "(>= y 0)", "(< y ch)", "(>= x 0)", "(< x cw)", "(<= (+ sx cw) sw)", "(<= (+ sy ch) sh)", "(<= (+ dx cw) dw)", "(<= (+ dy ch) dh)", "(= r2 (+ (* (+ y dy) sw) (+ x dx)))"], "(< r2 (* dw dh))", False)
T("M", "M9 3-D stride uses w for a", "w h d z y x a n r", BASE + ["(>= z 0)", "(< z d)", "(= a (* h w))", "(= n (* d a))", "(= r (+ (+ (* z w) (* y a)) x))"], "(< r n)", False)
T("N", "N1 regroup wrong", "y w c r", ["(= r (* (* y w) c))"], "(= r (* y (* w y)))", False)
T("N", "N2 buffer short by one row", "w h y x c ch r", BASE + ["(>= c 0)", "(<= c ch)", "(= r (+ (* (+ (* y w) x) ch) c))"], "(< r (* h (* w ch)))", False)
T("N", "N3 rotate90 wrong stride", "w h y x r", BASE + ["(= r (+ (* x w) (- (- h 1) y)))"], "(< r (* w h))", False)
T("N", "N4 bytes-get off by one", "w h y x b", ["(>= y 0)", "(< y h)", "(>= x 0)", "(<= x w)", "(= (bytesLen b) (* w h))"], "(< (+ (* y w) x) (bytesLen b))", False, {"b": "bytes"})
T("N", "N5 bytes read off by one, value", "w h y x b v", ["(>= y 0)", "(< y h)", "(>= x 0)", "(<= x w)", "(= (bytesLen b) (* w h))", "(= v (select b (+ (* y w) x)))"], "(< (+ (* y w) x) (bytesLen b))", False, {"b": "bytes"})
T("N", "N6 linear bug, callee post holds product", "w h p x", ["(= p (* w h))", "(>= x 0)"], "(>= x 1)", False)
T("N", "N7 linear bug beside a hard fact", "u v q x", ["(> u 0)", "(> v 0)", "(= q (* u u))", "(>= x 0)"], "(>= x 1)", False)
T("N", "N8 regrouped alias, wrong factor", "w h ch st y", ["(= st (* w ch))", "(>= y 0)", "(< y h)"], "(< (* y st) (* (* w h) y))", False)
T("N", "N9 goal false by normal form", "w h", [], "(< (* w h) (* h w))", False)
T("N", "N10 narrow row, stride too small", "w h y x st", BASE + ["(>= st 0)"], "(< (+ (* y w) x) (* h st))", False)
# ---- Y4M and netpbm, from the professor's battery. Sources: examples/y4m/raster.llmll, examples/netpbm-swarm/kernel.llmll
T("Y", "Y1 chroma plane <= luma plane", "w h cw ch", YB, "(<= (* cw ch) (* w h))")
T("Y", "Y2 U-plane offset inside the frame", "w h cw ch y x n r", YB + [NFR] + CUR + ["(< y ch)", "(< x cw)", "(= r (+ (* w h) (+ (* y cw) x)))"], "(and (>= r 0) (< r n))")
T("Y", "Y3 V-plane offset inside the frame", "w h cw ch y x n r", YB + [NFR] + CUR + ["(< y ch)", "(< x cw)", "(= r (+ (* w h) (+ (* cw ch) (+ (* y cw) x))))"], "(and (>= r 0) (< r n))")
T("Y", "Y4 frame at least luma+2", "w h cw ch n", YB + [NFR], "(>= n (+ (* w h) 2))")
T("Y", "Y5 frame at least 3/2 luma (W14 class)", "w h cw ch n", YB + [NFR], "(>= (* 2 n) (* 3 (* w h)))")
T("Y", "Y6 frame at most 3 luma", "w h cw ch n", YB + [NFR], "(<= n (* 3 (* w h)))")
T("Y", "Y7 chroma dims written inline", "w h", ["(>= w 1)", "(>= h 1)"], "(<= (* (/ (+ w 1) 2) (/ (+ h 1) 2)) (* w h))")
T("Y", "Y8 plane cursor from plane-w/plane-h posts", "w h p pw ph y x", PL + CUR + ["(< y ph)", "(< x pw)"], "(< (+ (* y pw) x) (* pw ph))")
T("Y", "Y9 plane area <= luma, cases in a post", "w h p pw ph", PL, "(<= (* pw ph) (* w h))")
T("Y", "Y10 luma plane area equals w*h, under p=0", "w h p pw ph", PL + ["(= p 0)"], "(= (* pw ph) (* w h))")
T("Y", "Y11 p>0 plane area equals inline chroma", "w h p pw ph", PL + ["(> p 0)"], "(= (* pw ph) (* (/ (+ w 1) 2) (/ (+ h 1) 2)))")
T("Y", "Y12 frame total from cases, any p", "w h p pw ph cw ch n", PL + YB[2:] + [NFR], "(<= (* pw ph) n)")
T("Y", "YF2 U offset, x<=cw (true: review's label corrected)", "w h cw ch y x n r", YB + [NFR] + CUR + ["(< y ch)", "(<= x cw)", "(= r (+ (* w h) (+ (* y cw) x)))"], "(< r n)")
T("K", "K1 channel 1 or 3 as a disjunct (kernel.llmll:44)", "c w i", ["(or (= c 1) (= c 3))", "(>= w 1)", "(>= i 0)", "(=> (= c 1) (< i w))", "(=> (= c 3) (< i (* 3 w)))"], "(< i (* c w))")
T("K", "K2 the same, channel fact split by if", "c w i", ["(= c 3)", "(>= w 1)", "(>= i 0)", "(< i (* 3 w))"], "(< i (* c w))")
T("K", "K3 row offset, variable channels", "c w h y k r", ["(>= c 1)", "(>= w 1)", "(>= y 0)", "(< y h)", "(>= k 0)", "(< k (* c w))", "(= r (+ (* y (* c w)) k))"], "(and (>= r 0) (< r (* h (* c w))))")
T("K", "K4 sample count below header limit", "c w h lim", ["(>= c 1)", "(>= w 1)", "(>= h 1)", "(<= (* (* w h) c) lim)"], "(<= (* w h) lim)")
T("K", "K5 row above in a blur", "y st x", ["(>= y 1)", "(>= st 0)", "(>= x 0)", "(< x st)"], "(>= (+ (* (- y 1) st) x) 0)")
T("K", "K6 crop window in a padded buffer", "y oy x ox c k st h0 w0", ["(>= y 0)", "(>= oy 0)", "(< (+ y oy) h0)", "(>= x 0)", "(>= ox 0)", "(< (+ x ox) w0)", "(>= c 1)", "(>= k 0)", "(< k c)", "(>= st (* w0 c))"], "(< (+ (* (+ y oy) st) (+ (* (+ x ox) c) k)) (* h0 st))")
T("K", "K7 half-scale of a product", "x sw w", ["(>= x 0)", "(< x w)", "(>= sw 0)"], "(<= (/ (* x sw) 2) (/ (* w sw) 2))")
T("K", "K8 last channel of a pixel, bytesLen", "w h ch y x k b", ["(>= w 1)", "(>= h 1)", "(>= ch 1)", "(>= y 0)", "(< y h)", "(>= x 0)", "(< x w)", "(>= k 0)", "(< k ch)", "(= (bytesLen b) (* (* w h) ch))"], "(< (+ (* (+ (* y w) x) ch) k) (bytesLen b))", True, {"b": "bytes"})
T("K", "K9 mod as a factor, written via div", "i w", ["(>= w 0)"], "(>= (* (- i (* 3 (/ i 3))) w) 0)")
T("K", "K10 RGB to row index, product of quotient", "i w y", ["(>= i 0)", "(< i (* 3 w))", "(>= y 0)"], "(>= (* (/ i 3) y) 0)")
T("K", "K11 quotient below width", "i w", ["(>= i 0)", "(>= w 1)", "(< i (* 3 w))"], "(< (/ i 3) w)")
T("K", "K12 stride equals padded row, two names", "w c pad st y x", ["(>= w 1)", "(>= c 1)", "(>= pad 0)", "(= st (+ (* w c) pad))", "(>= y 0)", "(>= x 0)", "(< x w)"], "(<= (+ (* y st) (* x c)) (* (+ y 1) st))")
T("K", "K13 weighted 3x3 kernel, nonneg", "a0 a1 a2 a3 a4 a5 a6 a7 a8 p0 p1 p2 p3 p4 p5 p6 p7 p8 r",[f"(>= a{i} 0)" for i in range(9)]+[f"(>= p{i} 0)" for i in range(9)]+["(= r (+ (* a0 p0) (+ (* a1 p1) (+ (* a2 p2) (+ (* a3 p3) (+ (* a4 p4) (+ (* a5 p5) (+ (* a6 p6) (+ (* a7 p7) (* a8 p8))))))))))"],"(>= r 0)")
T("YF", "YF3 frame omits one chroma plane", "w h cw ch y x n r", YB + ["(= n (+ (* w h) (* cw ch)))"] + CUR + ["(< y ch)", "(< x cw)", "(= r (+ (* w h) (+ (* cw ch) (+ (* y cw) x))))"], "(< r n)", False)
T("YF", "YF4 chroma floor, n/2 not (n+1)/2", "w h cw ch y x", ["(>= w 1)", "(>= h 1)", "(= cw (/ w 2))", "(= ch (/ h 2))", "(>= y 0)", "(< y h)"], "(>= (* cw ch) 1)", False)
T("KF", "KF1 channel disjunct, wrong bound", "c w i", ["(or (= c 1) (= c 3))", "(>= w 1)", "(>= i 0)", "(=> (= c 3) (<= i (* 3 w)))", "(=> (= c 1) (< i w))"], "(< i (* c w))", False)
T("KF", "KF2 crop, stride below row", "y x c st w0 h0", ["(>= y 0)", "(< y h0)", "(>= x 0)", "(< x w0)", "(>= c 1)", "(>= st c)"], "(< (+ (* y st) (* x c)) (* h0 st))", False)
T("KF", "KF3 blur row above at y=0", "y st x", ["(>= y 0)", "(>= st 1)", "(>= x 0)", "(< x st)"], "(>= (+ (* (- y 1) st) x) 0)", False)
T("KF", "KF4 last channel, ch-1 omitted", "w h ch y x k b", ["(>= w 1)", "(>= h 1)", "(>= ch 1)", "(>= y 0)", "(< y h)", "(>= x 0)", "(< x w)", "(>= k 0)", "(<= k ch)", "(= (bytesLen b) (* (* w h) ch))"], "(< (+ (* (+ (* y w) x) ch) k) (bytesLen b))", False, {"b": "bytes"})
T("PF", "PF plane copy, y<=h, src vs total", PV, PB + LET, "(< src total)", False)
T("PF", "PF2 plane copy, v vs luma only", PV, PB + LET, "(< v (+ luma chroma))", False)
# ---- O: two definitions of one atom, from the review
T("O", "O1 two definitions of x", "x y z w", ["(= x (+ y 1))", "(= x (* 2 z))"], "(= (* x w) (* 2 (* z w)))")
T("O", "O2 stride named twice", "w pad cw st y", ["(= st (+ w pad))", "(= st (* 2 cw))"], "(= (* y st) (* 2 (* y cw)))")
T("O", "O3 and in a pre, two products", "n w h c", ["(= n (* w h))", "(= n (* h c))"], "(= (* n w) (* w (* h c)))")
# ---- A: FQIte and mod atoms, new in Rev 3
T("A", "A1 abs as a factor", "dx st", ["(>= st 0)"], "(>= (* (abs dx) st) 0)")
T("A", "A2 mod as a factor", "i w", ["(>= w 0)"], "(>= (* (mod i 3) w) 0)")
T("A", "A3 mod below its divisor, scaled", "i w", ["(>= w 1)"], "(< (* (mod i 3) w) (* 3 w))")
T("A", "A4 max as a factor", "x w", ["(>= w 0)"], "(>= (* (max x 0) w) 0)")
T("A", "A5 product in an if branch", "x w", ["(>= w 0)"], "(>= (if (> x 0) (* x w) 0) 0)")
T("A", "A6 abs offsets in a raster", "dy dx w h", ["(< (abs dy) h)", "(< (abs dx) w)", "(>= w 1)"], "(< (+ (* (abs dy) w) (abs dx)) (* h w))")
T("A", "A7 interleaved channel by mod", "i w h y", ["(>= y 0)", "(< y h)", "(>= w 1)"], "(< (+ (* y (* 3 w)) (mod i 3)) (* h (* 3 w)))")
T("AF", "AF1 abs product can be zero", "dx st", ["(>= st 0)"], "(> (* (abs dx) st) 0)", False)
T("AF", "AF2 mod bound off by one", "i w", ["(>= w 1)"], "(< (* (mod i 3) w) (* 2 w))", False)
T("AF", "AF3 if factor with a negative branch", "x w", ["(>= w 0)"], "(>= (* (if (> x 0) x (- 0 1)) w) 0)", False)
# ---- B: arrays and strings in the emitter's encoding, new in Rev 3
T("B", "B1 byte square, needs byte-range", "v i b", ["(= v (select b i))"], "(<= (* v v) 65025)", True, {"b": "bytes"})
T("B", "B2 bytes-set keeps a product index in range", "w h y x b c", BASE + ["(= c (store b 0 7))", "(= (bytesLen c) (bytesLen b))", "(= (bytesLen b) (* w h))"], "(< (+ (* y w) x) (bytesLen c))", True, {"b": "bytes", "c": "bytes"})
T("B", "B3 strLen holds the product", "w h y x s", BASE + ["(= (strLen s) (* w h))"], "(< (+ (* y w) x) (strLen s))", True, {"s": "Str"})
T("B", "B4 two-array map, product key", "w y v hs vl hs2 vl2", ["(= hs2 (store hs (* y w) 1))", "(= vl2 (store vl (* y w) v))"], "(= (select hs2 (* w y)) 1)", True, {"hs": "intmap", "vl": "intmap", "hs2": "intmap", "vl2": "intmap"})
T("BF", "BF1 bytes-set, index off by one", "w h y x b c", ["(>= y 0)", "(< y h)", "(>= x 0)", "(<= x w)", "(= c (store b 0 7))", "(= (bytesLen c) (bytesLen b))", "(= (bytesLen b) (* w h))"], "(< (+ (* y w) x) (bytesLen c))", False, {"b": "bytes", "c": "bytes"})
T("BF", "BF2 byte value bound one short", "w h y x b c v", BASE + ["(= c (store b 0 7))", "(= v (select c (+ (* y w) x)))"], "(< (* 2 v) 510)", False, {"b": "bytes", "c": "bytes"})
T("BF", "BF3 read back the stored byte", "w y x b c v", ["(= y 0)", "(= x 0)", "(>= w 1)", "(= c (store b (+ (* y w) x) 7))", "(= v (select c (+ (* y w) x)))"], "(!= v 7)", False, {"b": "bytes", "c": "bytes"})
T("BF", "BF4 strLen, off by one", "w h y x s", ["(>= y 0)", "(< y h)", "(>= x 0)", "(<= x w)", "(= (strLen s) (* w h))"], "(< (+ (* y w) x) (strLen s))", False, {"s": "Str"})
T("BF", "BF5 two-array map, unwritten key", "w y k v hs vl hs2 vl2", ["(= hs2 (store hs (* y w) 1))", "(= vl2 (store vl (* y w) v))", "(>= k 0)"], "(= (select hs2 k) 1)", False, {"hs": "intmap", "vl": "intmap", "hs2": "intmap", "vl2": "intmap"})
T("BF", "BF6 equal strings, length off by one", "w h s t", ["(= s t)", "(>= (strLen s) (* w h))"], "(>= (strLen t) (+ (* w h) 1))", False, {"s": "Str", "t": "Str"})
T("BF", "BF7 distinct strings, equal length claim", "w h s t", ["(!= s t)", "(= (strLen s) (* w h))"], "(= (strLen t) (* w h))", False, {"s": "Str", "t": "Str"})
T("BF", "BF8 string-valued map, product key", "k j s t mv", ["(= (select mv k) s)", "(= (select mv j) t)", "(!= s t)"], "(!= (* k k) (* j j))", False, {"s": "Str", "t": "Str", "mv": "strmap"})
T("BF", "BF9 plane copy into a bytes buffer", "w h c pad y x st src b v", ["(>= w 1)", "(>= h 1)", "(>= c 1)", "(>= pad 0)", "(>= y 0)", "(<= y h)", "(>= x 0)", "(< x w)", "(= st (+ (* w c) pad))", "(= src (+ (* y st) (* x c)))", "(= (bytesLen b) (* h st))", "(= v (select b src))"], "(< src (bytesLen b))", False, {"b": "bytes"})


REV2_MISS = {"W14", "W23", "W25", "Q8", "Q9"}
REVIEW_MISS = {"Y5", "K1"}


def short(n):
    return n.split()[0]


def run_one(rec, tmo=120):
    vs, h, g = rec["w"]
    so = rec["sorts"]
    out = dict(name=rec["name"], group=rec["group"], truth=rec["truth"])
    try:
        t0 = time.process_time()
        s, vc, fx = build_smt(vs, h, g, so)
        q, vc2, _ = build_fq(vs, h, g, so)
        out["gen_cpu"] = round(time.process_time() - t0, 3)
    except Refused as e:
        out.update(verdict="fallback(refused)", z3="n/a", fp="n/a", cpu=0.0, T=0, facts=0, construct=e.construct, why=e.why, rc="n/a", model=None)
        return out
    z, zs = z3_run(s, 10)
    z = z.strip().split("\n")[0] if z.strip() else "empty"
    if vc2.rhs_true:
        r, c = "SAFE-NF", 0.0
    else:
        r, c = fixpoint(q, tmo)
    fam = {}
    for f in fx:
        fam[f[0]] = fam.get(f[0], 0) + 1
    rc = recheck(vs, h, g, so)
    out.update(z3=z, z3s=zs, fp=r, cpu=c, T=vc.T, facts=len(fx), fam=fam, capped=vc.capped, closure=vc.closure_size, maxdeg=vc.max_deg, rc=rc[0], rcwall=rc[1], rl=rc[2], model=rc[3])
    if r.startswith("SAFE"):
        out["verdict"] = "verified"
    elif r == "UNSAFE" and rc[0] == "sat" and rc[3] == "validated":
        out["verdict"] = "refuted"
    elif r == "UNSAFE":
        out["verdict"] = "fallback"
    else:
        out["verdict"] = "no-result"
    return out


# ---------------------------------------------------------------- invariance
def flip(t):
    if isinstance(t, list):
        if t[0] == "=":
            return ["=", flip(t[2]), flip(t[1])]
        return [t[0]] + [flip(x) for x in t[1:]]
    return t


def ren(t, m):
    if isinstance(t, list):
        return [t[0]] + [ren(x, m) for x in t[1:]]
    return m.get(t, t)


def flat_hyps(h, g, so):
    v = VC.__new__(VC)
    v.hyps = []
    for x in h:
        v.flat(x)
    return v.hyps


def variants(rec, rnd, k=2):
    """Yields (kind, vs, hyps, goal, sorts, renaming)."""
    vs, h, g = rec["w"]
    so = rec["sorts"]
    hs = flat_hyps(h, g, so)
    yield "reversed", vs, hs[::-1], g, so, {}
    for _ in range(k):
        x = list(hs)
        rnd.shuffle(x)
        yield "shuffled", vs, x, g, so, {}
    yield "flipped", vs, [flip(x) for x in hs], flip(g), so, {}
    for _ in range(k):
        pool = [f"v{i}" for i in range(len(vs))]
        rnd.shuffle(pool)
        m = dict(zip(sorted(vs), pool))
        yield "renamed", {m[v] for v in vs}, [ren(x, m) for x in hs], ren(g, m), ({m[a]: b for a, b in so.items()} if so else None), m
    for _ in range(k):
        x = [flip(y) for y in hs]
        rnd.shuffle(x)
        pool = [f"u{i}" for i in range(len(vs))]
        rnd.shuffle(pool)
        m = dict(zip(sorted(vs), pool))
        yield "combined", {m[v] for v in vs}, [ren(y, m) for y in x], ren(flip(g), m), ({m[a]: b for a, b in so.items()} if so else None), m


def fact_structs(vs, h, g, so, m):
    vc = VC(h, g, so)
    return {vc.s_fact(f, m) for f in vc.facts()}


def fact_structs_named(vs, h, g, so):
    vc = VC(h, g, so)
    return {vc.s_fact(f, {}) for f in vc.facts()}


def section_invariance(selected_names):
    print("\n--- 3 invariance of the fact set")
    rnd = random.Random(11)
    checks = fails = refused = 0
    failed = []
    for rec in TBL:
        vs, h, g = rec["w"]
        so = rec["sorts"]
        try:
            base = None
            vc = VC(h, g, so)
            fx = vc.facts()
        except Refused:
            refused += 1
            continue
        for kind, vs2, h2, g2, so2, m in variants(rec, rnd):
            b = {vc.s_fact(f, m) for f in fx}
            n = fact_structs_named(vs2, h2, g2, so2)
            checks += 1
            if b != n:
                fails += 1
                failed.append((short(rec["name"]), kind, len(b), len(n), len(b ^ n)))
    print(f"fact set equal after shuffle, flip, rename, combined: {checks} comparisons over {len(TBL)} witnesses, {fails} differ, {refused} witnesses refused", failed[:12])
    # control: the test must be able to fail. One rule per atom, in conjunct order, is Rev 2's reading
    global FIRST_ONLY
    FIRST_ONLY = True
    rnd2 = random.Random(11)
    ctl = []
    for rec in TBL:
        if short(rec["name"]) not in ("O1", "O2", "O3", "W18", "P6"):
            continue
        vs, h, g = rec["w"]
        vc = VC(h, g, rec["sorts"])
        fx = vc.facts()
        for kind, vs2, h2, g2, so2, m in variants(rec, rnd2):
            if {vc.s_fact(f, m) for f in fx} != fact_structs_named(vs2, h2, g2, so2):
                ctl.append((short(rec["name"]), kind))
    FIRST_ONLY = False
    print(f"control, one rule per atom in conjunct order: the same test differs on {len(ctl)} variants", sorted(set(ctl)))
    # byte identity of the fact block under conjunct shuffle and equation flip
    rnd = random.Random(12)
    same = diff = 0
    for rec in TBL:
        vs, h, g = rec["w"]
        so = rec["sorts"]
        try:
            _, vc, _ = build_fq(vs, h, g, so)
        except Refused:
            continue
        hs = flat_hyps(h, g, so)
        x = [flip(y) for y in hs]
        rnd.shuffle(x)
        _, vc2, _ = build_fq(vs, x, flip(g), so)
        if vc.fact_block == vc2.fact_block:
            same += 1
        else:
            diff += 1
    print(f"fact block byte-identical under shuffle and flip: {same} same, {diff} differ")
    # both solvers on the named witnesses and their variants
    print("named witnesses and variants, z3 with facts and fixpoint:")
    rnd = random.Random(5)
    disagree = []
    for name in selected_names:
        rec = next(r for r in TBL if short(r["name"]) == name)
        vs, h, g = rec["w"]
        so = rec["sorts"]
        rows = [("as written", vs, h, g, so)]
        for kind, vs2, h2, g2, so2, m in variants(rec, rnd):
            rows.append((kind, vs2, h2, g2, so2))
        res = []
        for kind, vs2, h2, g2, so2 in rows:
            s, _, _ = build_smt(vs2, h2, g2, so2)
            q, vc2, _ = build_fq(vs2, h2, g2, so2)
            z = z3_run(s, 10)[0].strip().split("\n")[0]
            r, c = ("SAFE-NF", 0.0) if vc2.rhs_true else fixpoint(q, 120)
            res.append((kind, z, r))
            if (z == "unsat") != r.startswith("SAFE"):
                disagree.append((name, kind, z, r))
        print(f"  {name:4s} " + " ".join(f"{k}:{z}/{r}" for k, z, r in res), flush=True)
    print("  z3 and fixpoint disagree on:", disagree)
    # every witness, one combined variant, both solvers
    rnd = random.Random(6)
    ch = []
    n = 0
    for rec in TBL:
        vs, h, g = rec["w"]
        so = rec["sorts"]
        try:
            s, _, _ = build_smt(vs, h, g, so)
            q0, v0, _ = build_fq(vs, h, g, so)
        except Refused:
            continue
        base_z = z3_run(s, 10)[0].strip().split("\n")[0]
        var = [x for x in variants(rec, rnd, 1) if x[0] == "combined"][0]
        _, vs2, h2, g2, so2, _ = var
        s2, _, _ = build_smt(vs2, h2, g2, so2)
        q2, v2, _ = build_fq(vs2, h2, g2, so2)
        z2 = z3_run(s2, 10)[0].strip().split("\n")[0]
        r2 = "SAFE-NF" if v2.rhs_true else fixpoint(q2, 120)[0]
        n += 1
        if z2 != base_z or (z2 == "unsat") != r2.startswith("SAFE"):
            ch.append((short(rec["name"]), base_z, z2, r2))
    print(f"every witness, one combined variant, z3 and fixpoint: {n} run, verdict changes or disagreements: {ch}")
    print("limit of the property: an equation with its terms moved, so that neither side is one atom, gives no rule")
    for label, hy in (("x=y+1, x=2z as written", ["(= x (+ y 1))", "(= x (* 2 z))"]), ("(x-y)=1, (x-2z)=0, terms moved", ["(= (- x y) 1)", "(= (- x (* 2 z)) 0)"])):
        vs, h, g = W("x y z w", hy, "(= (* x w) (* 2 (* z w)))")
        s, vc, fx = build_smt(vs, h, g)
        q, _, _ = build_fq(vs, h, g)
        print(f"  {label}: facts={len(fx)} z3={z3_run(s, 10)[0].split()[0]} fixpoint={fixpoint(q, 60)[0]} native={recheck(vs, h, g)[0]}", flush=True)


def hash_all():
    h = hashlib.sha256()
    for rec in TBL:
        vs, a, b = rec["w"]
        try:
            q, _, _ = build_fq(vs, a, b, rec["sorts"])
        except Refused as e:
            q = str(e)
        h.update(q.encode())
    return h.hexdigest()[:16]


def section_hashseed():
    print("\n--- 4 print order: whole .fq text of every witness under six hash seeds")
    seen = []
    for seed in ("0", "1", "2", "3", "42", "12345"):
        env = dict(os.environ, PYTHONHASHSEED=seed)
        p = subprocess.run([sys.executable, os.path.abspath(__file__), "--internal-hash"], capture_output=True, text=True, env=env)
        seen.append(p.stdout.strip() or p.stderr[-200:])
    print("  digests", sorted(set(seen)), "identical" if len(set(seen)) == 1 else "DIFFER")


# ---------------------------------------------------------------- scale under flat printing
def kernel(n):
    vs = [f"a{i}" for i in range(n)] + [f"p{i}" for i in range(n)] + ["r"]
    h = [f"(>= a{i} 0)" for i in range(n)] + [f"(>= p{i} 0)" for i in range(n)]
    t = f"(* a{n-1} p{n-1})"
    for i in reversed(range(n - 1)):
        t = f"(+ (* a{i} p{i}) {t})"
    return W(" ".join(vs), h + [f"(= r {t})"], "(>= r 0)")


def expand(k):
    groups = [[f"x{g}{i}" for i in range(k[g])] for g in range(len(k))]

    def s(xs):
        t = xs[-1]
        for x in reversed(xs[:-1]):
            t = f"(+ {x} {t})"
        return t
    t = s(groups[0])
    for g in groups[1:]:
        t = f"(* {t} {s(g)})"
    vv = [x for g in groups for x in g]
    return W(" ".join(vv) + " r", [f"(>= {x} 0)" for x in vv] + [f"(= r {t})"], "(>= r 0)")


def crux_rec():
    return next(r for r in TBL if short(r["name"]) == "W3")["w"]


def crux(K):
    vs, h, g = crux_rec()
    vs = set(vs)
    h = list(h)
    for i in range(K):
        a = f"a{i}"
        vs.add(a)
        h += [parse(f"(>= {a} 0)"), parse(f"(< {a} h)")]
        g = ["and", g, ["<", ["+", ["*", a, "w"], "x"], ["*", "w", "h"]]]
    return vs, h, g


def monotone(d):
    ls = [f"a{i}" for i in range(d)]
    us = [f"p{i}" for i in range(d)]
    h = [f"(>= {a} 0)" for a in ls] + [f"(<= {a} {u})" for a, u in zip(ls, us)]

    def pr(xs):
        t = xs[0]
        for x in xs[1:]:
            t = f"(* {t} {x})"
        return t
    return W(" ".join(ls + us), h, f"(<= {pr(ls)} {pr(us)})")


def run_scale(name, w, tmo=200, z3too=True):
    vs, h, g = w
    t0 = time.process_time()
    try:
        q, vc, fx = build_fq(vs, h, g)
    except Refused as e:
        print(f"  {name:34s} refused {e.construct}: {e.why} generator cpu={time.process_time()-t0:.2f} solver not called", flush=True)
        return
    gen = time.process_time() - t0
    r, c = ("SAFE-NF", 0.0) if vc.rhs_true else fixpoint(q, tmo)
    zt = ""
    if z3too:
        s, _, _ = build_smt(vs, h, g)
        o, zs = z3_run(s, 60)
        zt = f" z3={o.strip().split(chr(10))[0]} {zs}s"
    print(f"  {name:34s} T={vc.T} capped={vc.capped} closure={vc.closure_size} facts={len(fx)} bytes={len(q)} gen={gen:.2f} fixpoint={r[:30]} cpu={c}{zt}", flush=True)


def linear_fq(n, flat):
    vs = [f"x{i}" for i in range(n)]
    binds = [f"bind {i} {v} : {{ v : int | true }}" for i, v in enumerate(vs)]
    if flat:
        t = " + ".join(vs)
    else:
        t = vs[0]
        for v in vs[1:]:
            t = f"({t} + {v})"
    env = "; ".join(map(str, range(n)))
    return "\n".join(binds) + f"\nconstraint:\n  env [{env}]\n  lhs {{ VV : int | {' && '.join(f'{v} >= 0' for v in vs)} }}\n  rhs {{ VV : int | {t} >= 0 }}\n  id 0\n  tag [0]\n"


def paren_fq(depth):
    t = "x"
    for _ in range(depth):
        t = f"({t})"
    return f"bind 0 x : {{ v : int | true }}\nconstraint:\n  env [0]\n  lhs {{ VV : int | x >= 0 }}\n  rhs {{ VV : int | {t} >= 0 }}\n  id 0\n  tag [0]\n"


def section_scale():
    global MAX_WRITTEN
    print("\n--- 5 scale under flat printing, no written-pair cap unless stated")
    print(" no product: a linear sum, one goal; and redundant parens round one variable")
    for n, nt in ((12, 40), (16, 40), (20, 40), (80, 40)):
        a = fixpoint(linear_fq(n, False), nt) if n <= 20 else ("not run", 0)
        b = fixpoint(linear_fq(n, True), nt)
        print(f"  sum of {n}: nested {a[0]} cpu={a[1]} | flat {b[0]} cpu={b[1]}", flush=True)
    for dp in (12, 14, 16, 18):
        a = fixpoint(paren_fq(dp), 40)
        print(f"  parens depth {dp}: {a[0]} cpu={a[1]}", flush=True)
    print(" crux with K more product goals")
    for K in (2, 5, 10, 20, 40, 62, 63, 100):
        run_scale(f"crux K={K}", crux(K))
    print(" monotone degree")
    for d in (3, 4, 5, 6, 7):
        run_scale(f"monotone degree {d}", monotone(d), z3too=d <= 5)
    print(" long sums, no written-pair cap")
    for k in ([2, 2], [3, 3], [4, 4], [5, 5], [8, 8], [2, 2, 2], [3, 3, 2], [3, 3, 3], [4, 4, 4], [5, 5, 5], [7, 7, 7]):
        run_scale("x".join(map(str, k)) + " sums", expand(k))
    print(" long sums, written-pair cap 4 monomials")
    MAX_WRITTEN = 4
    for k in ([3, 3], [4, 4], [5, 5], [3, 3, 3], [4, 4, 4], [5, 5, 5]):
        run_scale("x".join(map(str, k)) + " sums, cap 4", expand(k))
    MAX_WRITTEN = None
    print(" kernels of separate products")
    for n in (9, 25, 49, 81, 121):
        run_scale(f"kernel {n} products", kernel(n))
    print(" pair cap is not local: the crux plus unrelated products")
    vs0, h0, g0 = crux_rec()
    for dg, counts in ((2, (10, 62, 63)), (3, (4, 10, 11)), (4, (2, 3))):
        for n in counts:
            vs = set(vs0)
            h = list(h0)
            for i in range(n):
                fs = [f"u{i}_{k}" for k in range(dg)]
                vs |= set(fs) | {f"t{i}"}
                t = fs[0]
                for f in fs[1:]:
                    t = f"(* {t} {f})"
                h.append(parse(f"(= t{i} {t})"))
            run_scale(f"crux + {n} unrelated degree {dg}", (vs, h, g0), tmo=120)
    section_nested()


def section_nested():
    global NESTED
    print(" same generator, nested sums and parens round a comparison, against flat")
    cases = [("W22", next(r for r in TBL if short(r["name"]) == "W22")["w"]), ("P3", next(r for r in TBL if short(r["name"]) == "P3")["w"]),
             ("crux K=20", crux(20)), ("3x3x3 sums", expand([3, 3, 3])), ("kernel 25 products", kernel(25))]
    for name, (vs, h, g) in cases:
        row = []
        for label, flag, tmo in (("nested", True, 70), ("flat", False, 120)):
            NESTED = flag
            q, vc, fx = build_fq(vs, h, g)
            row.append(f"{label}: {fixpoint(q, tmo)}")
        NESTED = False
        print(f"  {name:20s} facts={len(fx)} " + " | ".join(row), flush=True)


def section_overcap():
    global MONO
    print("\n--- 3b over the pair cap: F10 is omitted. Nested mul##nl keeps a congruence that aligns by name; one free symbol has none")
    for mono in ("uf", "sym"):
        MONO = mono
        for a, b, c, d in (("a", "b", "c", "d"), ("a", "c", "d", "b")):
            vs, h, g = W(f"{a} {b} {c} {d}", [f"(<= {a} {d})", f"(<= {d} {a})", f"(<= {b} {c})", f"(<= {c} {b})"], f"(= (* {a} {b}) (* {c} {d}))")
            vs = set(vs)
            h = list(h)
            for i in range(70):
                u, v, t = f"u{i}", f"v{i}", f"t{i}"
                vs |= {u, v, t}
                h.append(parse(f"(= {t} (* {u} {v}))"))
            s, vc, _ = build_smt(vs, h, g)
            q, _, _ = build_fq(vs, h, g)
            print(f"  {mono:3s} goal {a}*{b}={c}*{d}: T={vc.T} capped={vc.capped} z3={z3_run(s, 20)[0].split()[0]} fixpoint={fixpoint(q, 120)[0]}", flush=True)
    MONO = "sym"


def section_chain():
    print("\n--- 6 sigma bound: the chains stop inside the generator, before any solver call")
    before = dict(SOLVER_CALLS)
    for kind in ("sq1", "mix"):
        for n in (1, 2, 3, 4, 6, 8, 10, 12, 20, 40, 100):
            hy = []
            for i in range(n):
                hy.append(f"(= x{i+1} (+ (* x{i} x{i}) 1))" if kind == "sq1" else f"(= x{i+1} (+ (* x{i} y) z))")
            vs, h, g = W(" ".join(f"x{i}" for i in range(n + 1)) + " y z", hy, f"(>= (* x{n} x{n}) 0)")
            t = time.process_time()
            try:
                vc = VC(h, g)
                fx = vc.facts()
                res = f"ok T={vc.T} closure={vc.closure_size} maxdeg={vc.max_deg} facts={len(fx)}"
            except Refused as e:
                res = f"refused {e.construct}: {e.why}"
            print(f"  {kind} chain={n}: {res} generator cpu={time.process_time()-t:.3f}", flush=True)
    print("  solver calls during this section:", SOLVER_CALLS["z3"] - before["z3"], "z3,", SOLVER_CALLS["fixpoint"] - before["fixpoint"], "fixpoint")


def section_refusal():
    print("\n--- 7 refusal scan, before cancellation. No solver is called for a refusal")
    before = dict(SOLVER_CALLS)
    cases = [("C1 (* 0 (/ x y))", "x y", [], "(= (* 0 (/ x y)) 0)"),
             ("C2 (- (/ x y) (/ x y))", "x y", [], "(= (- (/ x y) (/ x y)) 0)"),
             ("C3 (* 0 (mod x y))", "x y", [], "(= (* 0 (mod x y)) 0)"),
             ("C4 (/ x 0)", "x", [], "(= (* 0 (/ x 0)) 0)"),
             ("C5 (/ x -2)", "x", [], "(>= (* x (/ x (- 0 2))) 0)"),
             ("C6 in a hypothesis", "x y w", ["(= w (* 0 (/ x y)))"], "(= w 0)"),
             ("C7 control (* 0 (/ x 2))", "x", [], "(= (* 0 (/ x 2)) 0)"),
             ("C8 control (mod x (+ 1 2))", "x w", ["(>= w 0)"], "(>= (* (mod x (+ 1 2)) w) 0)")]
    for name, v, h, g in cases:
        vs, hh, gg = W(v, h, g)
        try:
            vc = VC(hh, gg)
            fx = vc.facts()
            print(f"  {name}: accepted, facts={len(fx)}", flush=True)
        except Refused as e:
            print(f"  {name}: refused {e.construct}", flush=True)
    print("  solver calls during this section:", SOLVER_CALLS["z3"] - before["z3"], "z3,", SOLVER_CALLS["fixpoint"] - before["fixpoint"], "fixpoint")


def section_validator(rows):
    print("\n--- 8 validator: real z3 get-value output, arrays as finite maps, Str as tokens")
    show = ["PF", "PF2", "N5", "KF4", "BF1", "BF3", "BF5", "BF6", "BF7", "BF8", "BF9"]
    for name in show:
        rec = next(r for r in TBL if short(r["name"]) == name)
        vs, h, g = rec["w"]
        a = recheck(vs, h, g, rec["sorts"])
        print(f"  {name}: {a[0]} state={a[3]}")
        if a[4] and a[4].get("raw"):
            print(f"    get-value: {a[4]['raw'][:700]}")
    print(" controls: tamper one value in each validated model; the check must reject or the tampered model must be real")
    rej = acc = arrs = arrrej = toks = tokrej = apps_n = apprej = 0
    for rec in TBL:
        if rec["truth"]:
            continue
        vs, h, g = rec["w"]
        try:
            a = recheck(vs, h, g, rec["sorts"])
        except Refused:
            continue
        if a[3] != "validated":
            continue
        d = a[4]
        vc, env, apps, appv = d["vc"], d["env"], d["apps"], d["appv"]
        for v in list(env):
            e2 = dict(env)
            x = env[v]
            if isinstance(x, int):
                e2[v] = x + 1
            elif isinstance(x, FMap):
                # change the value at every index that the clause reads, and the default
                e2[v] = FMap((x.default + 1) if isinstance(x.default, int) else Token("Str!val!99"),
                             {k: (y + 1 if isinstance(y, int) else Token("Str!val!99")) for k, y in x.d.items()})
            else:
                e2[v] = Token("Str!val!99")
            st = validate(vc, h, g, e2, apps, appv)[0]
            if isinstance(x, FMap):
                arrs += 1
                arrrej += st != "validated"
            elif isinstance(x, Token):
                toks += 1
                tokrej += st != "validated"
            else:
                rej += st != "validated"
                acc += st == "validated"
        for i in range(len(appv)):
            a2 = list(appv)
            a2[i] = a2[i] + 1
            st = validate(vc, h, g, env, apps, a2)[0]
            apps_n += 1
            apprej += st != "validated"
    print(f"  int variables: rejected {rej}, still a counterexample {acc}")
    print(f"  arrays: {arrs} tampered, rejected {arrrej}")
    print(f"  Str tokens: {toks} tampered, rejected {tokrej}")
    print(f"  function results: {apps_n} tampered, rejected {apprej}")
    print(" control: function consistency. Equal strings with unequal strLen results must fail")
    rec = next(r for r in TBL if short(r["name"]) == "BF6")
    vs, h, g = rec["w"]
    d = recheck(vs, h, g, rec["sorts"])[4]
    a2 = list(d["appv"])
    a2[-1] = a2[-1] + 1
    print("  as read:", validate(d["vc"], h, g, d["env"], d["apps"], d["appv"]), "| one result changed:", validate(d["vc"], h, g, d["env"], d["apps"], a2))
    print(" control: byte-range stays in the query")
    rec = next(r for r in TBL if short(r["name"]) == "B1")
    vs, h, g = rec["w"]
    a = recheck(vs, h, g, rec["sorts"], ground_facts=True)
    b = recheck(vs, h, g, rec["sorts"], ground_facts=False)
    print(f"  B1 with byte-range: {a[0]}; without: {b[0]} state={b[3]} get-value={(b[4] or {}).get('raw', '')[:200]}")
    print("  (a validated sat without byte-range would be a false refuted, so the family must stay)")


def section_gen():
    print("\n--- 9 generator check: facts on exact values, normal form against the source")
    tot = bad = fired = nfn = nfbad = 0
    for rec in TBL:
        vs, h, g = rec["w"]
        try:
            a, b, c, d, e = gen_check(vs, h, g, rec["sorts"])
        except Refused:
            continue
        tot += a
        bad += b
        fired += c
        nfn += d
        nfbad += e
        if b or e:
            print("  BAD", rec["name"], a, b, e)
    print(f"  facts {tot}, failures {bad}, evaluations with a true premise {fired}; normal form evaluations {nfn}, differences {nfbad}")
    vac = []
    for rec in TBL:
        vs, h, g = rec["w"]
        try:
            t, vc, fx = build_smt(vs, h, g, rec["sorts"])
        except Refused:
            continue
        lines = t.split("\n")
        idx = [i for i, ln in enumerate(lines) if ln.startswith("(assert (not ")]
        t2 = "\n".join(lines[:idx[-1]] + lines[idx[-1] + 1:])
        o, _ = z3_run(t2, 10)
        if o.strip().split("\n")[0] != "sat":
            vac.append((short(rec["name"]), o[:20]))
    print("  hypotheses plus facts not satisfiable:", vac)
    print(" schema check: native z3 on Int (unsat = theorem), and on Real")
    SCHEMA = {
        "F1a": "(=> (and (>= a 0) (>= b 0)) (>= (* a b) 0))", "F1b": "(=> (and (<= a 0) (>= b 0)) (<= (* a b) 0))",
        "F2a": "(=> (= a 0) (= (* a b) 0))", "F2b": "(=> (= a 1) (= (* a b) b))", "F3": "(=> (and (>= a 1) (>= b 0)) (>= (* a b) b))",
        "F4": "(=> (and (<= a c) (<= b d) (>= b 0) (>= c 0)) (<= (* a b) (* c d)))",
        "F5": "(=> (and (< a c) (<= b d) (>= b 0) (>= c 0)) (<= (+ (* a b) b) (* c d)))",
        "F7": "(=> (and (>= a 0) (<= a 7) (>= b 0) (<= b 9)) (<= (* a b) 63))",
        "F7b-up": "(=> (and (<= a 7) (>= b 0)) (<= (* a b) (* 7 b)))", "F7b-lo": "(=> (and (>= a 7) (>= b 0)) (>= (* a b) (* 7 b)))",
        "F8": "(>= (* a a) 0)", "F9": "(=> (= a (+ c 1)) (= (* a b) (+ (* c b) b)))",
        "F10": "(=> (and (= a c) (= b d)) (= (* a b) (* c d)))", "F11": "(=> (= a 3) (= (* a b) (* 3 b)))",
        "mod bound": "(and (>= (mod a 3) 0) (<= (mod a 3) 2))",
        "control F5 no b>=0": "(=> (and (< a c) (<= b d) (>= c 0)) (<= (+ (* a b) b) (* c d)))",
        "control F7b no b>=0": "(=> (and (<= a 7)) (<= (* a b) (* 7 b)))",
        "control F11 wrong k": "(=> (= a 3) (= (* a b) (* 2 b)))",
    }
    for k, f in SCHEMA.items():
        res = []
        for sort in ("Int", "Real"):
            if "mod" in f and sort == "Real":
                res.append("n/a")
                continue
            q = "".join(f"(declare-const {v} {sort})" for v in "abcd") + f"(assert (not {f}))(check-sat)"
            o, _ = z3_run(q, 10)
            res.append(o.strip().split("\n")[0])
        print(f"  {k:24s} Int={res[0]:7s} Real={res[1]}")


def section_limits():
    print("\n--- 10 recheck limits: rlimit, no clock decision; three runs for stability on the design limit")
    F = [r for r in TBL if not r["truth"]]
    Tr = [r for r in TBL if r["truth"]]
    for lim in (200000, 2000000):
        res = {}
        for r in F + Tr:
            vs, h, g = r["w"]
            try:
                a = recheck(vs, h, g, r["sorts"], rlimit=lim)
            except Refused:
                res[short(r["name"])] = ("refused", 0, None, None)
                continue
            res[short(r["name"])] = a
        fn = [short(r["name"]) for r in F]
        tn = [short(r["name"]) for r in Tr]
        print(f"  rlimit {lim}: false sat {sum(res[n][0]=='sat' for n in fn)} of {len(fn)}, validated {sum(res[n][3]=='validated' for n in fn)}; others {[(n,res[n][0],res[n][3]) for n in fn if res[n][3]!='validated']}")
        print(f"    true sat {[n for n in tn if res[n][0]=='sat']}; not unsat {[(n,res[n][0],res[n][1]) for n in tn if res[n][0]!='unsat']}")
        print(f"    max false wall {max(res[n][1] for n in fn)}, max false rlimit {max((res[n][2] or 0) for n in fn)}, max true unsat rlimit {max((res[n][2] or 0) for n in tn if res[n][0]=='unsat')}")
    print(" noise: M1 with K unrelated products in scope")
    rec = next(r for r in TBL if short(r["name"]) == "M1")
    for K in (0, 8, 32):
        vs, h, g = rec["w"]
        vs = set(vs)
        h = list(h)
        for i in range(K):
            a, b, c = f"a{i}", f"b{i}", f"c{i}"
            vs |= {a, b, c}
            h += [parse(f"(>= {a} 1)"), parse(f"(>= {b} 1)"), parse(f"(= {c} (* {a} {b}))")]
        x = recheck(vs, h, g)
        print(f"  K={K}: {x[0]} {x[1]}s rlimit={x[2]} {x[3]}", flush=True)


def section_sites():
    print("\n--- 11 mark sites: a true claim that the facts do not prove, one site per row")

    def site(name, binders, lhs, goal, v):
        vs = set(v.split())
        env_h = [parse(x) for x in binders]
        hyps = env_h + [parse(x) for x in lhs]
        g = parse(goal)
        q, vc, fx = build_fq(vs, hyps, g, None, env_hyps=env_h)
        r, _ = ("SAFE-NF", 0.0) if vc.rhs_true else fixpoint(q, 60)
        marked = "mul##" in q
        rc = recheck(vs, hyps, g)
        verdict = "verified" if r.startswith("SAFE") else ("refuted" if rc[0] == "sat" and rc[3] == "validated" else "fallback") if marked else "refuted(linear)"
        print(f"  {name:34s} fixpoint={r:7s} marked={marked} recheck={rc[0]:7s} verdict={verdict}; with no mark: {'refuted' if r == 'UNSAFE' else 'verified'}", flush=True)
    X = ["(> x 0)", "(> y 0)"]
    site("S1 env binder", ["(= p (* x x))", "(= q (* 2 (* y y)))"], X, "(!= p q)", "x y p q")
    site("S2 lhs", [], X + ["(= p (* x x))", "(= q (* 2 (* y y)))"], "(!= p q)", "x y p q")
    site("S3 rhs", [], X, "(!= (* x x) (* 2 (* y y)))", "x y")
    site("S4 callee post, after substitution", ["(= call_0 (* x x))", "(= call_1 (* 2 (* y y)))"], X, "(!= call_0 call_1)", "x y call_0 call_1")
    site("S5 S9 definedness assumption", [], X + ["(= i (* x x))", "(= j (* 2 (* y y)))", "(>= i 0)"], "(!= i j)", "x y i j")
    site("S6 definedness goal", [], [], "(>= (- (* (+ a b) (+ a b)) (* 4 (* a b))) 0)", "a b")
    site("S7 env binder, W25 shape", ["(= p (* (+ a b) (+ a b)))", "(= q (* 4 (* a b)))"], [], "(>= p q)", "a b p q")
    site("S8 no product (control), false", [], ["(>= x 0)"], "(>= x 1)", "x")


def section_names():
    print("\n--- 12 names beside the reserved symbol")
    for b in ("mul", "mul_nl", "m_0", "mul_0"):
        txt = f"bind 0 {b} : {{ v : int | true }}\nbind 1 w : {{ v : int | true }}\nbind 2 mul##0 : {{ v : int | true }}\nconstraint:\n  env [0; 1; 2]\n  lhs {{ VV : int | mul##0 >= 1 && {b} >= 0 }}\n  rhs {{ VV : int | mul##0 >= 2 }}\n  id 7\n  tag [7]\n"
        print(f"  {b}: {fixpoint(txt, 30)[0]}", flush=True)


def main():
    t0 = time.time()
    print("z3", subprocess.run(["z3", "--version"], capture_output=True, text=True).stdout.strip(), "|", " ".join(subprocess.run(["fixpoint", "--version"], capture_output=True, text=True).stdout.split())[-30:])
    print("python", sys.version.split()[0], "| load", os.getloadavg(), "| mono", MONO, "| caps deg", MAX_DEG, "closure", MAX_CLOSURE, "poly", MAX_POLY, "pairs", MAX_PAIRS, "written", MAX_WRITTEN, "forms", FORMS_LIMIT, "rlimit", RLIMIT)
    print("\n--- 1 witness table: z3 with facts, fixpoint, recheck with a validated model")
    rows = []
    for rec in TBL:
        out = run_one(rec)
        rows.append(out)
        print(f"{out['name'][:50]:50s} {'T' if out['truth'] else 'F'} z3={out.get('z3'):7s} fixpoint={str(out.get('fp'))[:40]:8s} cpu={out.get('cpu',0):7.3f} T={out.get('T',0):3d} cl={out.get('closure','-')} facts={out.get('facts',0):5d} rc={out.get('rc')} rl={out.get('rl')} model={out.get('model')} => {out['verdict']}", flush=True)
    with open("r_rev3.json", "w") as f:
        json.dump(rows, f, indent=0, default=str)
    print("\n--- 2 summary")
    groups = sorted({r["group"] for r in rows})
    for g in groups:
        rs = [r for r in rows if r["group"] == g]
        tr = [r for r in rs if r["truth"]]
        fa = [r for r in rs if not r["truth"]]
        print(f"  {g:3s}: true proved {sum(r['verdict']=='verified' for r in tr)} of {len(tr)}, false refuted {sum(r['verdict']=='refuted' for r in fa)} of {len(fa)}")
    tr = [r for r in rows if r["truth"]]
    fa = [r for r in rows if not r["truth"]]
    print(f"  ALL: true proved {sum(r['verdict']=='verified' for r in tr)} of {len(tr)}; false refuted {sum(r['verdict']=='refuted' for r in fa)} of {len(fa)}")
    print("  true not proved:", [(short(r["name"]), r["verdict"], r["rc"]) for r in tr if r["verdict"] != "verified"])
    print("  false wrongly proved:", [short(r["name"]) for r in fa if r["verdict"] == "verified"])
    print("  false not refuted:", [(short(r["name"]), r["verdict"], r.get("rc"), r.get("model")) for r in fa if r["verdict"] != "refuted"])
    print("  true with a native sat:", [short(r["name"]) for r in tr if r.get("rc") == "sat"])
    print("  z3 and fixpoint disagree:", [short(r["name"]) for r in rows if r.get("z3") != "n/a" and (r.get("z3") == "unsat") != str(r.get("fp")).startswith("SAFE")])
    rl_f = [r.get("rl") or 0 for r in fa]
    rl_t = [r.get("rl") or 0 for r in tr if r.get("rc") == "unsat"]
    print("  max false rlimit", max(rl_f), "| max true unsat rlimit", max(rl_t), "| max false recheck wall", max(r.get("rcwall", 0) for r in fa))
    cpus = [r.get("cpu", 0) for r in rows]
    print("  cpu total", round(sum(cpus), 1), "median", statistics.median(cpus), "max", max((r.get("cpu", 0), short(r["name"])) for r in rows), "max facts", max((r.get("facts", 0), short(r["name"])) for r in rows), "max T", max((r.get("T", 0), short(r["name"])) for r in rows))
    rev2 = {short(r["name"]): r for r in rows}
    print("  Rev 2 misses now:", {n: rev2[n]["verdict"] for n in sorted(REV2_MISS)}, "| review misses now:", {n: rev2[n]["verdict"] for n in sorted(REVIEW_MISS)})
    print("  family totals:", {k: sum(r.get("fam", {}).get(k, 0) for r in rows) for k in ("F1", "F2", "F3", "F4", "F5", "F7", "F7b", "F8", "F9", "F10", "F11")})
    section_invariance(["O1", "O2", "O3", "Q8", "Q9", "K1"])
    section_overcap()
    section_hashseed()
    section_scale()
    section_chain()
    section_refusal()
    section_validator(rows)
    section_gen()
    section_limits()
    section_sites()
    section_names()
    print("\ndone. wall", round(time.time() - t0), "s | load", os.getloadavg(), "| solver calls", SOLVER_CALLS)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--internal-hash":
        print(hash_all())
    else:
        main()
