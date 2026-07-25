---
name: finding-fq-ctor-name-collision
title: "FQ-CTOR-COLLIDE-1: a binder named like a lowercased ADT constructor crashes the solver"
status: "OPEN — robustness/DX defect (fail-closed), found 2026-07-25 against v0.14.65"
severity: "fail-closed crash — never a false SAFE"
found_by: main-agent, during RFC-SWARM Phase 1 contract authoring
consumers: [compiler-engineer, user]
---

# FQ-CTOR-COLLIDE-1: a binder named like a lowercased ADT constructor crashes the solver

**One line.** The `.fq` emitter lowercases user ADT constructor names, so a parameter or
`let` binder whose name equals the lowercasing of **any** in-scope constructor collides with
it in the SMT namespace. liquid-fixpoint then crashes with a sort error naming a type the
function does not mention.

Unlike [MATCH-NULLARY-1](finding-match-nullary-ctor-unsound.md) this is **not** a soundness
bug: it fails closed. It is a usability trap, and a sharp one for a fill swarm, because the
colliding names are exactly the natural ones for protocol code (`denied`, `data`, `error`,
`ack`) and the error message points nowhere near the cause.

## Reproduction

```lisp
(type S (| Foo) (| Bar))

;; the parameter `bar` collides with the lowercasing of constructor `Bar`
(def-shell ca [bar: bool] -> int
  (post (=> bar (= result 1)) :source "[T001] ca")
  (if bar 1 0))
```

```
ERROR: liquid-fixpoint: crash: SMTLIB2 respSat = Error "Sort mismatch at argument #1
for function (declare-fun and (Bool Bool) Bool) supplied sort is S"
```

The identical function with a non-colliding parameter name verifies:

```lisp
(def-shell cb [flag: bool] -> int
  (post (=> flag (= result 1)) :source "[T001] cb")
  (if flag 1 0))
```
```
✅ SAFE (liquid-fixpoint)
```

Note that `S` appears in the error although `ca` neither takes nor returns an `S`. Merely
*declaring* the type in the module is enough, because the datatype declaration is emitted
into the same `.fq`.

A same-sort collision crashes too, with a different message:

```lisp
(def-shell cc [bar: S] -> bool
  (post (= result (= bar Foo)) :source "[T001] cc")
  (= bar Foo))
```
```
ERROR: elaborate solver failed on: VV##0 <=> bar == 0
  The sort S is not numeric ... Cannot unify S with int in expression: bar == 0
```

Renaming the parameter to `x` makes it verify SAFE, confirming the collision is the whole
cause in both shapes.

## Root cause

The emitted `.fq` declares the datatype with **lowercased** constructor names, then binds
the parameter under its own (already lowercase) name:

```
data XferState 0 = [ | idle { } | transferring { } | terminating { } | completed { } | denied { } | terminated { }]
bind 1 denied : { v : bool | true }
...
lhs { result : Packet | ... ((denied || fault) && ...) }
```

`denied` now names both the nullary `XferState` constant and a `bool` parameter. The solver
resolves the datatype constant and reports a sort mismatch on `||`.

The lowercasing is deliberate and consistent — `compiler/src/LLMLL/FixpointEmit.hs` applies
`T.toLower` to constructor names at lines 539, 2729, 2837, 3056, and 3621, and the comment
at line 3614 states the convention outright:

```haskell
-- lowercased to agree with emitCtor's `sanitizeFQId (toLower nm)`.
```

What is missing is that the constructor namespace and the binder namespace are then the
same flat namespace, with nothing keeping them apart.

## How it was found

Authoring the TFTP root contracts (RFC-SWARM Phase 1). `XferState` has a `Denied` state
(row T035) and `error-reply` naturally takes a `denied: bool` flag (rows T017/T089). 22 of
23 roots verified; that one crashed. The root contract now carries the parameter name
`refused` with a comment pointing here, which is a workaround in the artifact for a
compiler defect.

## Recommended fix `[CT]`

Separate the namespaces at emission. Preferred: qualify the emitted constructor symbol so
it cannot collide with any source-level identifier — e.g. emit `Denied` as `ctor$denied`
(or type-qualify as `xferstate$denied`, which additionally fixes same-named constructors in
two different ADTs). The change is local to `FixpointEmit.hs`'s `emitCtor` and the four
other `T.toLower` sites, which already share one convention.

Cheaper stopgap, if the emission change is deferred: detect the collision in the
typechecker and emit a **clear diagnostic** naming both the binder and the constructor,
rather than letting an opaque solver crash surface. That converts an unactionable failure
into an actionable one, which is most of the harm here.

Worth checking during the fix: `let`-bound names and `match` payload binders take the same
path as parameters and should be covered by the same test.

## Regression fixture

`compiler/test/fixtures/fq-ctor-collide/collide.llmll` (must verify SAFE once fixed; today
it crashes) and `control.llmll` (the non-colliding twin, SAFE today and after).
