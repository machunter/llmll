;; Step 3 — refine ordered: body = sequence fresh AND length sound; spawn both.
;; fill  /statements/2/body:
(and (seq-fresh seq last) (length-sound claimed received))
;; spawn:
(def-shell seq-fresh [seq: int last: int] -> bool
  (post (<=> result (> seq last))) ?impl)
(def-shell length-sound [claimed: int received: int] -> bool
  (post (<=> result (<= claimed received))) ?impl)
