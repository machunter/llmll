# Stage I: pre-registration

Write `PRE-REGISTRATION.md`, fixing in writing, **before any wave agent runs**:

1. **Acceptance criteria.** What counts as a successful fill, and what counts as a successful
   run overall.
2. **The measurement set.** Exactly which numbers will be reported, and over what denominator.
3. **Process budgets.** Semantic retries per hole; protocol-level (concurrency conflict)
   retries counted separately, so contention cannot consume an agent's error budget; human
   interventions after freeze.
4. **The numeric concurrency trigger.** How many agents, and what conflict rate would be
   treated as a finding.
5. **The mutant-class taxonomy**, per clause class, with any historically attested bug of this
   protocol as a mandatory member.

## The rule that gives this stage its value

**Pre-registration only means something if it is honored when it goes against you.** Record
outcomes in an appendix; never edit the pre-registered text. If an instrument you registered
turns out to be defective, do not quietly reinterpret it: append an amendment that states the
defect, shows the argument, and lets a human adjudicate.

There is precedent worth heeding. On the first run of this pipeline, a pre-registered
exclusion-ratio ceiling fired, and it was the *instrument* that was wrong: every clause in the
timing/transport class is excluded by the definition of the class, so the threshold was
breached by class assignment before any scoping judgment was made. The ratio measured the RFC's
genre composition, not the verifier's reach. It was retired by a written amendment, not by
being ignored. Do not re-introduce a ratio ceiling here.

## What to report, and what not to

Report **detection yield**: defects found and fixed, each with a concrete witness. Do not report
concordance or absence-of-failure. Agreement between two formalizations entails nothing, since
both could be wrong the same way, and shared training makes that likely. A metric that rises
when contracts get weaker is worse than no metric.

## The scope decision

{{scope}}

## The closed barrier list in force

{{barriers}}
