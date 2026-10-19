---
title: G7 tooling builtins — path-normalize, wasi.fs.list-kinds, ProcSpec and wasi.proc.exec
status: Rev 0, SETTLED 2026-10-18; amendments A1, A2 (implementation, 2026-10-18)
rows: PATH-NORM-1, LIST-KIND-1, PROC-ENV-1, PROC-REDIRECT-1 (G7)
review: none (the user skipped the professor step)
---

# G7 tooling builtins

**Status: Rev 0, SETTLED 2026-10-18.** The user settled all three items as written, including the `ProcSpec` type that also closes `PROC-REDIRECT-1`.

## Restatement

Three builtin additions remove shell-outs and hand-written workarounds from tooling programs. Each closes a roadmap row: `PATH-NORM-1`, `LIST-KIND-1` and `PROC-ENV-1`. For `PROC-ENV-1`, `docs/design/env-channel-proposal.md` Rev 2 §6 already fixes the shape, so that item also closes `PROC-REDIRECT-1`.

## Context located

**Measured on llmll 0.30.3**, with a console program built and run against a test directory:

| Probe | Answer |
|---|---|
| `wasi.fs.list` on a directory holding a file, a subdirectory, two symlinks, a dangling symlink and a FIFO | `RList [dangle, file, lfile, lsub, pipe, sub]`: names only, sorted |
| `wasi.fs.exists` on a file, a directory, a symlink to a file, a symlink to a directory | `file`, `dir`, `symlink`, `symlink` |
| `wasi.fs.exists` on a dangling symlink | `absent` |
| `wasi.fs.exists` on a FIFO | `file` |
| `wasi.fs.list` through a symlink loop (`sub/loop/loop`) | the link is followed and the listing answers |
| `wasi.proc.run "/usr/bin/env" ["FOO=bar" "/bin/sh" "-c" "echo $FOO"] …` | exit 0; the child printed `bar` |

1. `docs/design/env-channel-proposal.md` Rev 2 §6 (settled 2026-08-14). Do not add an eighth positional parameter to `wasi.proc.run`. Do not add a `wasi.env.set` that changes ambient state. Fold the environment into the redirection record that `PROC-REDIRECT-1` asks for. The record must add to the inherited environment, because replacing it takes `PATH` from the child.
2. `docs/compiler-team-roadmap.md`, row `PROC-REDIRECT-1` (DECIDE): one type for all three redirection paths that also absorbs the merge rule.
3. `compiler/src/LLMLL/TypeCheck.hs`, `builtinEnv`: `json-set` takes the sealed type `Json` (since `618a0984`, 2026-08-03) and `seq-commands` takes `Command`. The sealed opaque `Json` is the precedent for `ProcSpec`.
4. `tools/doc-path-lint/pathlint.llmll`, `norm-join`: the hand-written normalization `PATH-NORM-1` cites. It drops a leading `..` and a leading `/`.
5. `compiler/src/LLMLL/CodegenHs.hs`, `wasi_fs_exists`: the symlink test runs after a probe that follows the link, so a dangling link answers `absent` (a recorded residue). The FIFO answer comes from the fallback "not a directory, so a file".

**Findings, routed to documentation-lead:**

- (a) `LLMLL.md` §13.9 says "There is no `wasi.http.get`"; the table above that sentence documents `wasi.http.get`.
- (b) The `PROC-REDIRECT-1` row says no builtin takes a `TCustom` argument. Item 3 above refutes that.
- (c) The `LIST-KIND-1` row's symlink concern is answered per entry by `wasi.fs.exists`, and the row does not say so.
- (d) `wasi.fs.exists` answers `file` for a FIFO. The spec lists four answers and does not disclose this case.

## Design proposal

### 1. `PATH-NORM-1`: `path-normalize`

`path-normalize : string -> string`. Pure and total; callable from `def` and `def-shell`; no capability.

Lexical POSIX normalization (Python `posixpath.normpath`), with one stated difference in rule 4:

1. The empty string answers `"."`.
2. A path is absolute if and only if it starts with `/`.
3. Split on `/`. Drop empty segments and `.` segments.
4. A `..` removes the previous segment when one exists and is not `..`. Otherwise a relative path keeps the `..`, and an absolute path drops it (`/..` is `/`). A leading `//` becomes `/`; Python keeps it, and POSIX leaves it implementation-defined.
5. Join with `/`, with a leading `/` for an absolute path. An empty result answers `/` for an absolute path and `.` for a relative one.

| Input | Output |
|---|---|
| `a/b/../c` | `a/c` |
| `../a` | `../a` |
| `/../a` | `/a` |
| `a/` | `a` |
| `./` | `.` |

**Soundness.** A pure total function from string to string, with no effect, no state and no failure. It does not read the filesystem, so `a/link/../c` answers `a/c` whatever `link` points to. The spec says so, as Python's documentation does.

### 2. `LIST-KIND-1`: `wasi.fs.list-kinds`

`wasi.fs.list-kinds : string -> Command`, under `(import wasi.fs (capability read PATH))`, with `wasi.fs.list`'s effect label.

It delivers `RList`. Each entry is a one-letter kind, one space, and the name:

- `f`: a regular file
- `d`: a directory
- `l`: a symlink, decided without following it, so a dangling link is `l`
- `o`: anything else (FIFO, socket, device)

Entries are sorted by name, as `wasi.fs.list` sorts them. The prefix is always two characters, so `(string-slice e 2 (string-length e))` is the name, also when the name holds a space or a newline. A directory that cannot be read delivers `RErr`, as `wasi.fs.list` does.

**Why a new name.** Changing `wasi.fs.list` changes the meaning of every caller. A new `Response` arm breaks every exhaustive `match` on `Response`. One `wasi.fs.exists` per entry costs N+1 steps, because a program gets one response per step and `seq-commands` keeps only the last; it also carries the FIFO and dangling-link answers above.

**Soundness.** A read with `wasi.fs.list`'s authority, on the existing `RList` arm. It changes no state. It does not follow or classify a symlink's target: a tree walker skips `l` entries, which ends the symlink-cycle concern the row records, and a program that needs the target kind calls `wasi.fs.exists`.

### 3. `PROC-ENV-1` and `PROC-REDIRECT-1`: `ProcSpec` and `wasi.proc.exec`

`ProcSpec` is a sealed opaque type, like `Json`: no constructors, no `match`, and a program may not redefine the name. These pure functions build it:

| Function | Signature | Meaning |
|---|---|---|
| `proc-spec` | `int -> ProcSpec` | The timeout in seconds, required. Defaults: working directory `"."`, stdin `/dev/null`, stdout and stderr discarded, environment inherited |
| `proc-cwd` | `ProcSpec string -> ProcSpec` | Set the working directory |
| `proc-stdin` | `ProcSpec string -> ProcSpec` | Read stdin from a path |
| `proc-stdout` | `ProcSpec string -> ProcSpec` | Write stdout to a path |
| `proc-stderr` | `ProcSpec string -> ProcSpec` | Write stderr to a path |
| `proc-stderr-to-stdout` | `ProcSpec -> ProcSpec` | Merge stderr into stdout |
| `proc-env` | `ProcSpec string string -> ProcSpec` | Add one variable (name, value) over the inherited environment; a later call with the same name wins |

A setter called twice keeps the last value. `proc-stderr` after `proc-stderr-to-stdout` cancels the merge, and the reverse order sets it again.

`wasi.proc.exec : string list[string] ProcSpec -> Command`, under `(import wasi.proc (capability exec NAME))`. It delivers `RCode` with the child's exit status, and `RErr` for a timeout, a missing executable or an IO failure, as `wasi.proc.run` does.

```lisp
(wasi.proc.exec "make" ["test"]
  (proc-env (proc-stdout (proc-spec 120) "out.log") "LC_ALL" "C"))
```

**Check-time rules.** A literal `proc-env` name that is empty or contains `=` is a type error, on the `wasi.env.get` precedent. A literal `proc-spec` timeout below 1 is a type error. A computed bad name or timeout delivers `RErr` from `wasi.proc.exec` before the child starts.

**Equal paths.** `proc-stdout` and `proc-stderr` naming one string open the file twice, as a shell's `>f 2>f` does. The spec says so and names `proc-stderr-to-stdout` as the merge.

**`wasi.proc.run` is unchanged**, and so is every program that calls it. The spec directs new code to `wasi.proc.exec`.

**Soundness.** Every `ProcSpec` function is pure and answers a new value, so strict immutability holds. The environment applies to one child and never to the program, which is the env-channel rule, and it adds to the inherited environment. Each redirection is set by name, so a swap of the stdout and stderr paths is no longer a silent permutation, and the merge is an operation rather than string equality. The authority is `wasi.proc.run`'s: one namespace, one capability, and no runtime capability check (§7).

## Edge cases and degenerate inputs

| # | Input | Expected | Channel |
|---|---|---|---|
| 1 | `(path-normalize "a/b/../c")` | `"a/c"`. The row's witness: 58 of 947 lint citations contain `..` | test |
| 2 | `(path-normalize "../../a")`, `(path-normalize "/../a")` | `"../../a"`, `"/a"`. `norm-join` answers `"a"` for the first, so this is a positive witness that the builtin differs from the workaround | test |
| 3 | `(path-normalize "")` | `"."`, never `""` | test |
| 4 | any string, normalized twice | equal to one normalization; no `//`, no `/./`, no trailing `/` except `/` itself | property test |
| 5 | `a/link/../c` with `link` a symlink | `"a/c"` | spec is silent (intentional): lexical only, disclosed |
| 6 | `wasi.fs.list-kinds` on the measured directory | `["l dangle","f file","l lfile","l lsub","o pipe","d sub"]` | end-to-end test |
| 7 | `wasi.fs.list-kinds` on an empty directory, a missing directory, a file | `RList []`, `RErr`, `RErr` | end-to-end test |
| 8 | an entry name holding a space or a newline | the prefix stays two characters; the name round-trips | end-to-end test |
| 9 | `(proc-env s "" "x")`, `(proc-env s "A=B" "x")` | type error: the positive witness for the guard. A computed bad name delivers `RErr` | type |
| 10 | `proc-env` sets `LC_ALL` to `C`; the child runs `/bin/sh -c 'echo $LC_ALL $PATH'` | prints `C` and the parent's `PATH`: the variable is added, and the environment is not replaced | end-to-end test |
| 11 | `(proc-spec 0)`, `(proc-spec -1)` | type error for a literal; `RErr` for a computed value | type |
| 12 | `proc-stderr-to-stdout`, then `proc-stderr "e.log"` | stderr goes to `e.log`: the last setter wins | test |

## Verification mapping

No proof obligation is introduced.

- `path-normalize` and the `ProcSpec` functions are opaque builtins outside `Σ_auto` (`LLMLL.md` §5.3.3). A `def` that calls one falls back to `asserted`. Edge case 4 is a property test, not a proof.
- `wasi.fs.list-kinds` and `wasi.proc.exec` build `Command` values and declare no fact. The `RCode` of `wasi.proc.exec` is an exit status the operating system decides.
- Trust: `wasi.fs.list-kinds` joins the filesystem-read clause in `ObligationAssembly.primEffect`. `wasi.proc.exec` takes the lattice top, as `wasi.proc.run` does (amendment A1).

## Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`: `builtinEnv` entries for `path-normalize`, `wasi.fs.list-kinds`, the seven `ProcSpec` functions and `wasi.proc.exec`; the two literal-argument rules.
- `compiler/src/LLMLL/TypeAdmissibility.hs`: `ProcSpec` joins the sealed type names, on the `Json` path.
- `compiler/src/LLMLL/CodegenHs.hs`: runtime bodies; `ProcSpec` as a Haskell record; `exec` passes the inherited environment plus the overrides (`System.Process` replaces the environment when given one); `list-kinds` classifies without following a symlink.
- `compiler/src/LLMLL/ObligationAssembly.hs`: effect clauses for the two `wasi.*` names.
- `docs/llmll-ast.schema.json`: no node change; these are ordinary applications.
- `LLMLL.md`, by documentation-lead after shipping: §3.2 a `ProcSpec` row; §13.6 `path-normalize`; §13.9 rows for `wasi.fs.list-kinds` and `wasi.proc.exec`, a note that directs new code from `run` to `exec`, and findings (a) and (d).
- `docs/compiler-team-roadmap.md`, by documentation-lead: `PATH-NORM-1`, `LIST-KIND-1`, `PROC-ENV-1` and `PROC-REDIRECT-1` close.

## Risks

1. **Scope.** `PROC-ENV-1` cannot ship as a parameter, so the batch also decides and closes `PROC-REDIRECT-1`, a DECIDE row. Settled as one batch.
2. **Two process commands.** Keeping `wasi.proc.run` avoids breaking programs and leaves two forms. Retiring `run` is a later decision and is not proposed here.
3. **Dependency.** Telling `o` from `f` may add the `unix` package to a generated project that calls `wasi.fs.list-kinds`. `FS-EXISTS-1` avoided that dependency. The fallback is three kinds, with a FIFO reported as `f`. Four kinds are settled; the engineer reports the cost.
4. **Argument order.** `proc-env`'s name and value are both strings, so a swap type-checks. The literal rule catches only a name position holding `=` or nothing.
5. **Platform.** `wasi.fs.list-kinds` and `wasi.proc.exec` are specified for POSIX, as `wasi.proc.run` is.

## Amendments

**A1 (implementation plan, 2026-10-18): `wasi.proc.exec` takes the lattice top.** Rev 0 said each new `wasi.*` name needs an effect clause. That holds for `wasi.fs.list-kinds`, which joins the filesystem-read clause. It does not hold for `wasi.proc.exec`. `ObligationAssembly.primEffect` gives `wasi.proc.run` the top on purpose: the effect summary is a may-over-approximation, and a spawned program may do anything. A `ProcSpec` bounds where the child's handles and environment point, not what the child does. So `wasi.proc.exec` takes the top too, and a test pins it. No behaviour changes from Rev 0's intent.

**A2 (measured during implementation, 2026-10-18): a relative redirection path resolves against the calling program's directory.** `wasi.proc.exec` opens the stdout, stderr and stdin files itself, before the child starts. A relative path in `proc-stdout`, `proc-stderr` or `proc-stdin` therefore resolves against the calling program's working directory, not against `proc-cwd`. `wasi.proc.run` behaves the same way. Measured: `(proc-stdout (proc-cwd (proc-spec 10) d) "out")` wrote `out` in the program's directory and not in `d`. The spec states this. A caller that wants the file beside the child passes an absolute path.
