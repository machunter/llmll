# RFC 4648: operator prediction, recorded before the run

> Written 2026-07-26, **before** launching. Committed before the driver starts so it
> cannot be retrofitted to whatever happens. Compiler v0.14.67, driver at `18264a4`.

## Why this target

Two runs have now passed every gate. **No stop condition has ever fired for a real
reason:** gate J passed on TFTP and on ARP, and gate L only ever failed because of a
hardcoded tag prefix in my own lint, which was then bypassed by the resume bug rather
than halting properly.

A method whose stop conditions have never stopped anything has not shown that it has
working stop conditions. This run exists to fire one.

RFC 4648 (Base16/Base32/Base64) was chosen because it is **plausibly attemptable**. It
talks about octets and groups of bits, its normative rules are crisp, and nothing on its
surface announces that it is out of reach. A reasonable person would try it. A target
obviously beyond the fragment, like a hash function, would make a refusal meaningless.

## What I expect, in order of confidence

1. **The run STOPs at gate J on the characteristic-core condition.** The core of a
   base-N encoding specification is the encode/decode correspondence: 24 bits regrouped
   into four 6-bit symbols, with padding. That is bit-regrouping over a sequence plus
   alphabet membership, which is the same B5 string-structure wall that took ARP's
   `8 + 2*ar$hln + ar$pln`. I expect stage F to name it as core and stage G to have to
   exclude it.

2. **Failing that, a STOP at gate J on the barrier list**, if the dispositioner reaches
   for a reason the closed list does not carry.

3. **Failing both, completion with very low coverage.** I predict carried C1+C2+C3
   **below 20%** if it completes at all, against ARP's 55.3% and TFTP's corrected 78.5%.

## What would falsify the instrument

**A green kill matrix.** If RFC 4648 runs to completion with a healthy carried fraction
and mutants refuting, then either the core was drawn narrowly enough to dodge the wall,
or the gates do not bite. Both are findings, and the second is serious: it would mean
the STOPs are decorative and the two prior passes meant less than claimed.

## What this run does NOT test

Whether the method predicts fit in advance. I already hold the expectation above, so
this tests the instrument, not the forecast. A blind fit test is a different experiment.

## Cost note

If the gates work, a bad-fit run is **cheap**: it halts at J, having spent only stages A
through I, and never reaches the wave. An expensive bad-fit run is itself evidence that
something failed to halt.
