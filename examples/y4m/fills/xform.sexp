;; Bodies for the holes of holed/xform.llmll. Applied by tools/fill.py
;; through `llmll checkout` + `llmll patch --require-proof`.

;; ?hflip-src-body
(- (- pw 1) x)

;; ?crop-ok-body
(and (>= x0 0) (and (>= y0 0) (and (= (mod x0 2) 0) (and (= (mod y0 2) 0)
  (and (>= cw 1) (and (>= ch 1)
  (and (<= (+ x0 cw) w) (<= (+ y0 ch) h))))))))

;; ?crop-keep-body
(if (= p 0)
    (and (and (<= x0 x) (< x (+ x0 cw))) (and (<= y0 y) (< y (+ y0 ch))))
    (let [(cx (/ x0 2)) (cy (/ y0 2)) (ccw (chroma-dim cw)) (cch (chroma-dim ch))]
      (and (and (<= cx x) (< x (+ cx ccw))) (and (<= cy y) (< y (+ cy cch))))))

;; ?crop-chroma-fits-body
true

;; ?hex-hi-body
(/ b 16)

;; ?hex-lo-body
(mod b 16)

;; ?digit-code-body
(+ 48 d)
