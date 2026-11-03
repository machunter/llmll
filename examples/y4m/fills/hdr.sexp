;; Bodies for the holes of holed/hdr.llmll. Applied by tools/fill.py
;; through `llmll checkout` + `llmll patch --require-proof`.

;; ?is-digit-body
(and (>= b 48) (<= b 57))

;; ?num-step-body
(if (= v -2) -2
  (if (or (< b 48) (> b 57)) -2
    (if (= v -1) (- b 48) (+ (* 10 v) (- b 48)))))

;; ?param-tag-body
(if (= b 87) 1
(if (= b 72) 2
(if (= b 70) 3
(if (= b 73) 4
(if (= b 65) 5
(if (= b 67) 6
(if (= b 88) 7 0)))))))

;; ?magic-byte-body
(if (= i 0) 89
(if (= i 1) 85
(if (= i 2) 86
(if (= i 3) 52
(if (= i 4) 77
(if (= i 5) 80
(if (= i 6) 69
(if (= i 7) 71 50))))))))

;; ?chroma-420-body
(and (= b1 52) (and (= b2 50) (= b3 48)))

;; ?header-problem-body
(if (= w -1) 1
(if (< w -1) 2
(if (= h -1) 3
(if (< h -1) 4
(if (or (< w 1) (> w 16384)) 5
(if (or (< h 1) (> h 16384)) 6
(if (and (= rn -1) (= rd -1)) 7
(if (or (< rn 0) (< rd 0)) 8
(if (or (= rn 0) (= rd 0)) 9
(if (not c420) 10 0))))))))))
