;; Step 2 — refine authenticated: body = MAC matches AND handshake up; spawn both.
;; fill  /statements/1/body:
(and (mac-matches computed expected) (handshake-up hs_state))
;; spawn:
(def-shell mac-matches [computed: int expected: int] -> bool
  (post (<=> result (= computed expected))) ?impl)
(def-shell handshake-up [hs_state: int] -> bool
  (post (<=> result (= hs_state 2))) ?impl)
