;; Bodies for the holes of holed/ybuf.llmll. Applied by tools/fill.py
;; through `llmll checkout` + `llmll patch --require-proof`.

;; ?find-lf-body
(if (< i (bytes-length buf))
    (if (= (bytes-get buf i) 10) i (find-lf buf (+ i 1)))
    -1)

;; ?marker-end-body
(if (>= i (bytes-length buf)) -2
  (let [(k2 (marker-step k (bytes-get buf i)))]
    (if (= k2 -1) -1 (if (= k2 6) (+ i 1) (marker-end buf (+ i 1) k2)))))

;; ?luma-plane-body
(bytes-slice fr 0 (* w h))

;; ?crop-row-body
(bytes-slice (bytes-slice pl ro (+ ro pw)) x0 (+ x0 cw))

;; ?hflip-at-body
(bytes-get row (hflip-src (bytes-length row) ox))
