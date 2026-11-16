# Template-fit count: TFTP (RFC 1350) and ARP (RFC 826)

Date 2026-11-15. Retrospective: each Encoded inventory row is matched, by the leading `[cid]` of `:source`,
to the clauses that cite it in the frozen root contracts, and every top-level conjunct is sorted by
which clause-sheet template (language-team proposal, Part 3) could produce it.

Inputs: `examples/tftp_rfc1350/roots/tftp.llmll`, `experiments/rfc-swarm/runs/rfc826/roots.llmll`,
and the two `inventory-dispositioned.json` files. Scripts: `extract.py`, `classify.py` (this folder).

## Result

| | TFTP | ARP | Combined |
|---|---|---|---|
| Encoded rows (all cited by a root clause) | 46 | 39 | 85 |
| Fit an existing template | 39 (85%) | 35 (90%) | 74 (87%) |
| Need "SHALL NOT return t" | 4 (T009 T011 T022 T118) | 2 (A30 A65) | 6 |
| Need "SHALL return one of {a, b}" | 2 (T069 T070) | 2 (A79 A82) | 4 |
| Need "SHALL return t ONLY WHEN g" | 1 (T012) | 0 | 1 |

"Fit" counts REQUIRES, WHEN, and unconditional RETURN, plus one range clause (T050) that becomes a
return-type refinement in the vocabulary, plus six ARP clauses that are bool-result WHENs or nested
WHENs that flatten mechanically. No row needed the generic `ENSURES <p>` escape, apart from the 11 gap
rows. With the three added templates, 85/85 fit.

By class: every C2 and C3 row fits except one C3 (T050 via vocabulary, one SHALL NOT); all 11 gaps
sit in C1 transition rows, plus one C4.

## What this does and does not show

- Shows: the template set is expressive enough for every contract these runs actually froze. The
  "templates too narrow" risk does not bind on this corpus.
- The 11 gap rows are all deliberately partial specs (a value excluded, a set of allowed values).
  These are exactly the inputs that example pinning reports as underdetermined, so each needs a
  recorded MAY-style freedom or pinning will raise a question on every example.
- Does not show that a developer would write these sentences from scratch. The guards
  (`key-present?`, `owns-target?`, `supports?`, enum constants) are vocabulary decisions; the
  templates are easy because the vocabulary already did the interpretive work.
- Three ARP precondition clauses (on `arp-frame`, `arp-merge`, `arp-add`) carry no `:source`.
  They encode the RFC's branch split and are modeling decisions with no provenance (language-team F-1).
- Excluded rows are outside the denominator. Templates do nothing for them.
