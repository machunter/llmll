# Stage K: root contract authoring

Author the LLMLL **root contracts** that carry every `Encoded` inventory row. Write them to
`roots.llmll` in your working directory.

## The rule that defines this stage

**One contract clause per `Encoded` inventory row, each carrying its own `:source`, opened by
the bracketed row tag.**

```lisp
(post (=> (and (= st Transferring) (= len 512)) (= result Transferring))
  :source "[T065] RFC 1350 lines 361-362 - a full 512-byte data field means the transfer continues")
```

The bracketed `[Tnnn]` tag is what makes coverage mechanically checkable. Matching free prose
would be fuzzy, and a completeness claim cannot rest on fuzzy matching. A citation whose tag is
not an inventory row, a missing row, or a citation of an excluded row each fail the lint and
halt the pipeline.

Per-conjunct provenance means a multi-clause `pre` or `post` keeps **every** citation, so do
**not** distort the design into one-clause-per-function to make traceability work. Write the
contract the protocol wants, and give each conjunct its own clause and citation.

## Bodies are holes

Every function body is `?impl`. You are authoring **what must be true**, not how. The bodies
are invented later by a swarm of agents that will never see a reference solution, and writing
one here would destroy the experiment.

## Staying inside the body-faithful fragment

A contract the verifier cannot discharge is a trap for the swarm. Constraints that hold in the
shipped compiler:

- **Discriminate on nullary enum tags, not on payload-bearing ADT parameters.** A `match` ON a
  payload-bearing ADT parameter falls back from body-faithful verification; CONSTRUCTING one
  does not. So pass a decoded tag plus scalars, and return a constructed value.
- **Constructors are nullary or single-payload.** A record with two fields is not expressible
  as one constructor; carry the extra fields as sibling parameters.
- **A bare `string` compared to a literal falls back.** Model an enumerated wire field as a
  decoded enum, not as a string.
- **A nullary constructor in a `match` arm is written `((Idle) ...)`, never `(Idle ...)`.** The
  bare form is a binder and is rejected.
- **Do not name a parameter after a constructor** of any type in the module, even a different
  one: the emitted constraint file lowercases constructor names and the two collide, crashing
  the solver.
- **Import no ordering the RFC does not define.** If sequence numbers have no defined ordering
  or rollover in the source, reason by equality, disequality, and successor only.

## Self-check before you finish

Run `{{llmll}} check roots.llmll`. It must typecheck. The pipeline will additionally run the
coverage lint in both directions and will not proceed until it passes.

## The scope decision

{{scope}}

## The `Encoded` rows you must carry (one clause each)

{{encoded}}

## The pinned RFC text

```
{{rfc_text}}
```
