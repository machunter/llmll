;; Step 1 — refine admit-byte: body = authenticated AND ordered; spawn both sub-holes.
;; fill  /statements/0/body:
(and (authenticated computed expected hs_state) (ordered seq last claimed received))
;; spawn:
(def-shell authenticated [computed: int expected: int hs_state: int] -> bool
  (post (<=> result (and (= computed expected) (= hs_state 2)))) ?impl)
(def-shell ordered [seq: int last: int claimed: int received: int] -> bool
  (post (<=> result (and (> seq last) (<= claimed received)))) ?impl)
