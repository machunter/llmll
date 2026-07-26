# Stage N: the refute layer

Author the pre-registered mutant taxonomy against the implemented tree. Write each mutant to
your working directory, then write `mutants.json`.

**Do NOT verify the mutants yourself.** The driver runs `llmll verify` on every entry and
scores the matrix; that is its job, not yours, and it has no turn limit. Your deliverable is
the mutant files plus `mutants.json`, and nothing else. Two runs of this stage were lost to an
agent spending its whole budget on solver time and never writing `mutants.json` at all: the
mutants existed and the catalogue that makes them scoreable did not. Write the catalogue
FIRST, then stop.

```json
[
  {"name": "sorcerers-apprentice", "file": "m-sorcerers-apprentice.llmll",
   "targets": ["T113"],
   "bug": "resends the current DATA packet on a duplicate ACK"},
  {"name": "good-twin-explicit-else", "file": "m-good-twin.llmll",
   "good_twin": true,
   "targets": [],
   "bug": "a correct variant written differently; must stay SAFE"}
]
```

## The language reference is in your directory

`LLMLL.md` (the language specification) and `llmll-ast.schema.json` (the machine-readable
JSON-AST shape) are present. Read them: they define the syntax, the type system, and which
predicates the verifier can discharge automatically. They say nothing about the target
specification, so consulting them is not a shortcut, it is the tool manual.

## Build the mutants carefully

Each mutant changes **one** thing, in a function body, and the change must be the specific
wrong behavior you name. Two failure modes to avoid, both seen in practice:

- **A mutation that lands somewhere else.** If you edit by string replacement and the body is a
  single token such as `Terminated` or `st`, the replacement can hit a comment or a type
  declaration instead of the body. The result "survives" and looks like a weak contract when it
  is really a broken instrument. Verify that the mutant's body actually changed.
- **A mutation nothing forbids.** If the mutant is a behavior the RFC permits, it should
  survive, and it is a `good_twin`, not a failure.

## Include good twins

Retain correct variants expected to stay SAFE. They are the guard against over-strong
contracts: a contract set that refutes everything, including correct implementations, is as
useless as one that refutes nothing.

## Survivors are reported, not dropped

A mutant that verifies SAFE means the contract is weak or the row is mis-dispositioned. The
pipeline reports the **full** kill matrix including survivors, and each survivor is resolved
rather than quietly removed from the taxonomy.

## Read the result correctly

A killed mutant proves the contract **excludes one specific behavior**. That is eliminative
evidence. It does **not** corroborate that the contract says what the RFC says: one side of
that question is English prose and it has no formal answer. Do not write "the contracts were
validated" anywhere.

## The pre-registered taxonomy

{{prereg}}

## The implemented tree

```lisp
{{tree}}
```
