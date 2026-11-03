;; Bodies for the holes of holed/raster.llmll. Applied by tools/fill.py
;; through `llmll checkout` + `llmll patch --require-proof`.

;; ?chroma-dim-body
(/ (+ n 1) 2)

;; ?plane-w-body
(if (= p 0) w (/ (+ w 1) 2))

;; ?plane-h-body
(if (= p 0) h (/ (+ h 1) 2))

;; ?next-x-body
(let [(pw (if (= p 0) w (/ (+ w 1) 2)))]
  (if (< (+ x 1) pw) (+ x 1) 0))

;; ?next-y-body
(let [(pw (if (= p 0) w (/ (+ w 1) 2)))
      (ph (if (= p 0) h (/ (+ h 1) 2)))]
  (if (< (+ x 1) pw) y (if (< (+ y 1) ph) (+ y 1) 0)))

;; ?next-p-body
(let [(pw (if (= p 0) w (/ (+ w 1) 2)))
      (ph (if (= p 0) h (/ (+ h 1) 2)))]
  (if (or (< (+ x 1) pw) (< (+ y 1) ph)) p (if (= p 2) 0 (+ p 1))))

;; ?frame-end-body
(and (= p 2) (and (= (+ x 1) (/ (+ w 1) 2)) (= (+ y 1) (/ (+ h 1) 2))))

;; ?marker-step-body
(if (= k 0) (if (= b 70) 1 -1)
(if (= k 1) (if (= b 82) 2 -1)
(if (= k 2) (if (= b 65) 3 -1)
(if (= k 3) (if (= b 77) 4 -1)
(if (= k 4) (if (= b 69) 5 -1)
(if (= k 5) (if (= b 10) 6 (if (= b 32) 7 -1))
    (if (= b 10) 6 7)))))))
