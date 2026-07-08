;; Guardrail — ORPHAN spawn: a def the fill body never calls. The scope safety
;; predicate REJECTS the refine ("not referenced by the fill body").
;; spawn (rejected):
(def-shell audit-log [entry: int] -> bool
  (post (<=> result (>= entry 0))) ?impl)
