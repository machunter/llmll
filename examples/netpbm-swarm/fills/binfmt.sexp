;; Bodies for the holes of holed/binfmt.llmll. Applied by tools/fill.py
;; through `llmll checkout` + `llmll patch --require-proof`.

;; ?byte-class-body
(if (or (= b 9) (or (= b 10) (or (= b 11) (or (= b 12) (or (= b 13) (= b 32)))))) 0
(if (and (>= b 48) (<= b 57)) 1
(if (= b 35) 2 3)))

;; ?header-end-body
(if (>= i (bytes-length buf)) -1
  (let [(b (bytes-get buf i))]
    (if (= ic 1)
        (if (or (= b 10) (= b 13))
            (if (>= nt 4) (+ i 1) (header-end buf (+ i 1) nt 0 0))
            (header-end buf (+ i 1) nt 0 1))
        (if (or (= b 9) (or (= b 10) (or (= b 11) (or (= b 12) (or (= b 13) (= b 32))))))
            (if (= it 1)
                (if (>= (+ nt 1) 4) (+ i 1) (header-end buf (+ i 1) (+ nt 1) 0 0))
                (header-end buf (+ i 1) nt 0 0))
            (if (= b 35)
                (header-end buf (+ i 1) (+ nt it) 0 1)
                (header-end buf (+ i 1) nt 1 0))))))

;; ?raster-len-body
(let [(n (* w h)) (k (if (= c 1) 1 3)) (b (if (< m 256) 1 2))]
  (* b (* k n)))

;; ?bin-sample-body
(if (= b 1)
    (bytes-get buf (+ off i))
    (+ (* 256 (bytes-get buf (+ off (+ i i)))) (bytes-get buf (+ (+ off (+ i i)) 1))))
