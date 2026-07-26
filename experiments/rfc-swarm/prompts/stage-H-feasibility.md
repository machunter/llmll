# Stage H: feasibility probes, before authoring anything

Prove the core contract shapes actually verify **and** actually refute, before the pipeline
commits to this target.

## What to produce

For each probe: a small LLMLL program exercising one protocol-core shape, and a **mutant** of
it carrying a plausible bug. Write both files into your working directory, then write
`probes.json` describing them.

```json
[
  {"name": "sender-step",
   "file": "sender-step.llmll",
   "mutant_file": "sender-step-mutant.llmll",
   "bug": "resends the current DATA packet on a duplicate ACK (the Sorcerer's Apprentice bug)"}
]
```

## The language reference is in your directory

`LLMLL.md` (the language specification) and `llmll-ast.schema.json` (the machine-readable
JSON-AST shape) are present. Read them: they define the syntax, the type system, and which
predicates the verifier can discharge automatically. They say nothing about the target
specification, so consulting them is not a shortcut, it is the tool manual.

## The bar

The pipeline runs `{{llmll}} verify <file> --strict-verified-core` on both and requires:

- the probe: **SAFE** and **body-faithful**
- the mutant: **not SAFE** (refuted)

**A contract that cannot refute its own historically-attested bug is decorative.** If a mutant
verifies SAFE, the contract is too weak; strengthen it and probe again rather than proceeding.

Probe at least the main transition function and any joint or product invariant the architecture
will need. Where the protocol has a famous bug, that bug is a mandatory mutant.

## Do not write a reference solution

These probe bodies are working implementations of functions the swarm is meant to invent. They
stay in this directory and are never promoted into the deliverable. Carry forward the contract
shapes and the verdicts only.

## Language constraints worth knowing

- A nullary constructor in a `match` arm is written `((Idle) ...)`, never `(Idle ...)`.
- Do not name a parameter after any constructor in the module.
- Matching on a payload-bearing ADT parameter loses body-faithfulness; discriminate on nullary
  tags plus scalars and return constructed values.

## The scope decision

{{scope}}
