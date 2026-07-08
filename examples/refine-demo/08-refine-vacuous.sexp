;; Guardrail — VACUOUS spawn: authenticated's post is weakened to an implication a
;; constant `true` body already satisfies. The CDP vacuity gate REJECTS the refine.
;; spawn (rejected):
(def-shell authenticated [computed: int expected: int hs_state: int] -> bool
  (post (=> (and (= computed expected) (= hs_state 2)) result)) ?impl)
