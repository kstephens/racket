
;; These are true for beginner, but the operators are syntax, so
;; arity-test doesn't work.

(htdp-syntax-test #'local)
(htdp-syntax-test #'(local))
(htdp-syntax-test #'(local ()))
(htdp-syntax-test #'(local 1))
(htdp-syntax-test #'(local 1 1))
(htdp-syntax-test #'(local () 1 2))
(htdp-syntax-test #'(local [1] 1 2))
(htdp-syntax-test #'(local [(+ 1 2)] 1))
(htdp-syntax-test #'(local [(define x)] 1))
(htdp-syntax-test #'(local [(lambda (x) x)] 1))
(htdp-syntax-test #'(local [(define x 1) (define x 2)] 1))
(htdp-syntax-test #'(local [(define (x a) 12) (+ 1 2)] 1))

(htdp-err/rt-test (local [(define x y) (define y 5)] 10) exn:fail:contract:variable?)

(htdp-test 1 'local (local () 1))
(htdp-test 5 'local (local [(define y 5) (define x y)] x))
(htdp-test #t 'local (local [(define (even n) (if (zero? n) true (odd (sub1 n))))
			(define (odd n) (if (zero? n) false (even (sub1 n))))]
		       (even 100)))
(htdp-test 19 (local [(define (f x) (+ x 10))] f) 9)
(htdp-test 16 'local (local [(define (f x) (+ x 10))] (f 6)))

(htdp-syntax-test #'letrec)
(htdp-syntax-test #'(letrec))
(htdp-syntax-test #'(letrec ()))
(htdp-syntax-test #'(letrec 1 2))
(htdp-syntax-test #'(letrec 1 2 3))
(htdp-syntax-test #'(letrec (10) 1))
(htdp-syntax-test #'(letrec ([x]) 1))
(htdp-syntax-test #'(letrec ([x 2 3]) 1))
(htdp-syntax-test #'(letrec ([x 5] 10) 1))
(htdp-syntax-test #'(letrec ([1 5]) 1))
(htdp-syntax-test #'(letrec ([1 5 6]) 1))
(htdp-syntax-test #'(letrec ([x 5]) 1 2))
(htdp-syntax-test #'(letrec ([x 5][x 6]) 1))

(htdp-err/rt-test (letrec ([x y] [y 5]) 10) exn:fail:contract:variable?)

(htdp-test 1 'letrec (letrec () 1))
(htdp-test 5 'letrec (letrec ([y 5][x y]) x))
(htdp-test #t 'letrec (letrec ([even (lambda (n) (if (zero? n) true (odd (sub1 n))))]
			  [odd (lambda (n) (if (zero? n) false (even (sub1 n))))])
		   (even 100)))
(htdp-test 19 (letrec ([f (lambda (x) (+ x 10))]) f) 9)
(htdp-test 16 'letrec (letrec ([f (lambda (x) (+ x 10))]) (f 6)))

(htdp-syntax-test #'let)
(htdp-syntax-test #'(let))
(htdp-syntax-test #'(let ()))
(htdp-syntax-test #'(let 1 2))
(htdp-syntax-test #'(let 1 2 3))
(htdp-syntax-test #'(let (10) 1))
(htdp-syntax-test #'(let ([x]) 1))
(htdp-syntax-test #'(let ([x 2 3]) 1))
(htdp-syntax-test #'(let ([x 5] 10) 1))
(htdp-syntax-test #'(let ([1 5]) 1))
(htdp-syntax-test #'(let ([1 5 6]) 1))
(htdp-syntax-test #'(let ([x 5]) 1 2))
(htdp-syntax-test #'(let ([x 5][x 6]) 1))

(htdp-test 1 'let (let () 1))
(htdp-test 5 'let (let ([y 5]) (let ([x y]) x)))
(htdp-test 6 'let (let ([y 6]) (let ([y 10][x y]) x)))
(htdp-test 19 (let ([f (lambda (x) (+ x 10))]) f) 9)
(htdp-test 16 'let (let ([f (lambda (x) (+ x 10))]) (f 6)))

(htdp-syntax-test #'let*)
(htdp-syntax-test #'(let*))
(htdp-syntax-test #'(let* ()))
(htdp-syntax-test #'(let* 1 2))
(htdp-syntax-test #'(let* 1 2 3))
(htdp-syntax-test #'(let* (10) 1))
(htdp-syntax-test #'(let* ([x]) 1))
(htdp-syntax-test #'(let* ([x 2 3]) 1))
(htdp-syntax-test #'(let* ([x 5] 10) 1))
(htdp-syntax-test #'(let* ([1 5]) 1))
(htdp-syntax-test #'(let* ([1 5 6]) 1))
(htdp-syntax-test #'(let* ([x 5]) 1 2))

(htdp-test 1 'let* (let* () 1))
(htdp-test 6 'let* (let* ([x 5][x 6]) x))
(htdp-test 9 'let* (let* ([x 8][x (add1 x)]) x))
(htdp-test 5 'let* (let* ([y 5]) (let* ([x y]) x)))
(htdp-test 10 'let* (let* ([y 6]) (let* ([y 10][x y]) x)))
(htdp-test 19 (let* ([f (lambda (x) (+ x 10))]) f) 9)
(htdp-test 16 'let* (let* ([f (lambda (x) (+ x 10))]) (f 6)))

(htdp-test 7779 'time (time 7779))
(htdp-syntax-test #'time)
(htdp-syntax-test #'(time))
(htdp-syntax-test #'(time 1 2))
(htdp-syntax-test #'(time (define x 5)))

(htdp-err/rt-test (foldr car 2 '(1 2 3))
  "foldr : first argument must be a <procedure> that accepts two arguments, given #<procedure:car>")

(htdp-err/rt-test (foldl car 2 '(1 2 3))
  "foldl : first argument must be a <procedure> that accepts two arguments, given #<procedure:car>")

(htdp-err/rt-test (build-string 2 add1)
  "build-string : second argument must be a <procedure> that produces a <char>, given #<procedure:add1>, which produced 1 for 0")

(htdp-test 0 '+ (+))
(htdp-test 1 '+ (+ 1))
(htdp-test 1 '* (*))
(htdp-test 1 '* (* 1))
;(htdp-test (-) exn:application:arity?)
;(htdp-err/rt-test (/) exn:application:arity?)
;(htdp-test 1 (/ 1) exn:application:arity?)
