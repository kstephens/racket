#lang frtime
(require frtime/etc)
(define x (rec y (0 . until . (add1 (inf-delay y)))))

(==> (filter-e zero? (changes (modulo seconds 10)))
     (lambda (v)
       (printf "~S~n" (value-now x))))