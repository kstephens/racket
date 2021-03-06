
(load-relative "loadtest.rktl")

(Section 'macro)

(error-test #'(define-syntaxes () (values 1)) exn:application:arity?)
(error-test #'(define-syntaxes () (values 1 2)) exn:application:arity?)
(error-test #'(define-syntaxes (x) (values 1 2)) exn:application:arity?)
(error-test #'(define-syntaxes (x y) (values 1)) exn:application:arity?)
(error-test #'(define-syntaxes (x y) (values 1 2 3)) exn:application:arity?)

;; Declarations:
(define-syntaxes (x) (values))
(define-syntaxes (x y) (values))

(define-syntax mx
  (lambda (stx)
    (syntax-case stx ()
      [(_ x)
       (syntax (x 1 8))])))
(test 9 'macro (mx +))
(test -7 'macro (mx -))
(test 18 'macro (let ([mx (lambda (x) (x 1 8 9))]) (mx +)))

(define-syntax (m stx)
  (syntax-case stx ()
    [(_) #'(m2 x)]))

(define-syntax (m2 stx)
  (syntax-case stx ()
    [(_ y) #'(let ([y 10]
		   [x 8])
	       y)]))

(test 10 'hygiene (m))
(test 10 'hygiene (m2 y))
(test 10 'hygiene (m2 x))
(test 10 'hygiene (eval #'(m)))
(test 10 'hygiene (eval (expand #'(m))))
(test 10 'hygiene (eval (expand (expand #'(m)))))

(define-syntax define-foo
  (syntax-rules ()
    ((_ expr) (define foo expr))))

(test 'o 'hygiene (let ()
		    (define-foo 'f)
		    (define-foo 'o)
		    (define o 'o)
		    o))
(test 'o 'hygiene (eval (expand (expand #'(let ()
					    (define-foo 'f)
					    (define-foo 'o)
					    (define o 'o)
					    o)))))


(test 13 'let-macro (let-syntax ([mx (lambda (stx)
				       (syntax-case stx ()
					 [(_ x) (syntax (x 6 7))]))])
		      (mx +)))
(test -7 'let-macro (let-syntax ([mx2 (lambda (stx)
					(syntax-case stx ()
					  [(_ x y) (syntax (mx y))]))])
		      (mx2 + -)))
(test '(10) 'let-macro ((lambda () (let-syntax ([x (lambda (stx)
						     (syntax-case stx ()
						       [(_ v) (syntax (list v))]))])
				     (x 10)))))

(test '(10) 'let-macro (let () 
			 (define-syntax x
			   (lambda (stx)
			     (syntax-case stx ()
			       [(_ v) (syntax (list v))])))
			 (x 10)))
(test '(10) 'let-macro ((lambda () 
			  (define-syntax x
			    (lambda (stx)
			      (syntax-case stx ()
				[(_ v) (syntax (list v))])))
			  (x 10))))

(test 55 (let ()
	   (define-syntax (g x) #'f)
	   (define (f x) x)
	   (define h g)
	   h)
      55)

(test 66 (let ()
	   (define (f x) x)
	   (define-syntax (g x) #'f)
	   (define h g)
	   h)
      66)

(test 77 (let ()
	   (define (f x) x)
	   (define h g)
	   (define-syntax (g x) #'f)
	   h)
      77)

(test 55 (letrec-syntaxes+values ([(g) (lambda (x) #'f)])
				 ([(f) (lambda (x) x)]
				  [(h) f])
	   h)
      55)

(test 7 'lrsv (letrec-syntaxes+values () () 7))

(syntax-test #'(set! lambda 5))
(syntax-test #'(lambda () (define-syntax x 10) (set! x 5)))
(syntax-test #'(lambda () (define-syntax (x) 10) (set! x 5)))

(syntax-test #'letrec-syntaxes+values)
(syntax-test #'(letrec-syntaxes+values))
(syntax-test #'(letrec-syntaxes+values . 1))
(syntax-test #'(letrec-syntaxes+values ()))
(syntax-test #'(letrec-syntaxes+values () . 1))
(syntax-test #'(letrec-syntaxes+values () ()))
(syntax-test #'(letrec-syntaxes+values () () . 1))
(syntax-test #'(letrec-syntaxes+values x () 1))
(syntax-test #'(letrec-syntaxes+values (x) () 1))
(syntax-test #'(letrec-syntaxes+values ([x]) () 1))
(syntax-test #'(letrec-syntaxes+values ([(x)]) () 1))
(syntax-test #'(letrec-syntaxes+values ([(x) 1 2]) () 1))
(syntax-test #'(letrec-syntaxes+values ([(x) 1] . y) () 1))
(syntax-test #'(letrec-syntaxes+values () x 1))
(syntax-test #'(letrec-syntaxes+values () (x) 1))
(syntax-test #'(letrec-syntaxes+values () ([x]) 1))
(syntax-test #'(letrec-syntaxes+values () ([(x)]) 1))
(syntax-test #'(letrec-syntaxes+values () ([(x) 1 2]) 1))
(syntax-test #'(letrec-syntaxes+values () ([(x) 1] . y) 1))

(test 7 'set!-transformer
      (let ([x 3])
	(let-syntax ([f (make-set!-transformer
			 (lambda (stx)
			   (syntax-case stx ()
			     [(_ __ val)
			      #'(set! x val)])))])
	  (set! f 7)
	  x)))

(test 77 'set!-transformer-prop
      (let ([x 3])
	(let-syntax ([f (let ()
                          (define-struct s!t (proc)
                            #:property prop:set!-transformer 0)
                          (make-s!t
                           (lambda (stx)
                             (syntax-case stx ()
                               [(_ __ val)
                                #'(set! x val)]))))])
	  (set! f 77)
	  x)))

(test 777 'set!-transformer-prop2
      (let ([x 3])
	(let-syntax ([f (let ()
                          (define-struct s!t ()
                            #:property prop:set!-transformer
                            (lambda (stx)
                              (syntax-case stx ()
                                [(_ __ val)
                                 #'(set! x val)])))
                          (make-s!t))])
	  (set! f 777)
	  x)))

(test 7 'rename-transformer
      (let ([x 3])
	(let-syntax ([f (make-rename-transformer #'x)])
	  (set! f 6)
	  (set! x (add1 x))
	  f)))

(test 5 'rename-with-non-hygiene
      (let-syntax ([f (lambda (stx) (datum->syntax stx 'foo))])
	(let-syntax ([g (make-rename-transformer #'f)])
	  (let ([foo 5])
	    g))))

(test 12 'rename-with-non-hygiene/app
      (let-syntax ([f (lambda (stx) 
			   (syntax-case stx ()
			     [(_ arg)
			      #`(#,(datum->syntax stx 'foo) arg)]))])
	(let-syntax ([g (make-rename-transformer #'f)])
	  (let ([foo (lambda (x) (sub1 x))])
	    (g 13)))))

(test 43 'rename-with-non-hygiene/set
      (let-syntax ([f (make-set!-transformer
			  (lambda (stx) 
			    (syntax-case stx ()
			      [(set! _ arg)
			       #`(set! #,(datum->syntax stx 'foo) arg)])))])
	(let-syntax ([g (make-rename-transformer #'f)])
	  (let ([foo 45])
	    (set! g 43)
	    foo))))

(define foo 88)
(test 88 'rename-with-hygiene
      (let-syntax ([g (make-rename-transformer #'foo)])
	(let ([foo 5])
	  g)))

(define (foox w) (+ w 88))
(test 99 'rename-with-hygiene/app
      (let-syntax ([g (make-rename-transformer #'foox)])
	(let ([foox 5])
	  (g 11))))

(define fooy 12)
(test '(5 11) 'rename-with-hygiene/set!
      (list (let-syntax ([g (make-rename-transformer #'fooy)])
	      (let ([fooy 5])
		(set! g 11)
		fooy))
	    fooy))

(test 12 'rename-internal-define
      (let-syntax ([fooz (syntax-rules ()
			   [(_ id) (define id 12)])])
	(let-syntax ([foozzz (make-rename-transformer #'fooz)])
	  (foozzz foozz)
	  foozz)))

(test #t set!-transformer? (make-set!-transformer void))
(test #t rename-transformer? (make-rename-transformer #'void))

(err/rt-test (make-set!-transformer 5))
(err/rt-test (make-set!-transformer #'x))
(err/rt-test (make-rename-transformer 5))
(err/rt-test (make-rename-transformer void))

(arity-test make-set!-transformer 1 1)
(arity-test set!-transformer? 1 1)
(arity-test make-rename-transformer 1 2)
(arity-test rename-transformer? 1 1)

;; Test inheritance of context when . is used in a pattern

(define-syntax keep-context
  (syntax-rules () [(a . b) b]))
(define-syntax (discard-context stx) 
  (syntax-case stx () 
    [(v . a) (datum->syntax #f (syntax-e #'a))]))

(test 6 'plus (keep-context + 1 2 3))
(test 6 'plus (keep-context . (+ 1 2 3)))

(unless building-flat-tests?
  (eval-syntax
   #'(test 6 'plus (discard-context keep-context . (+ 1 2 3)))))

(syntax-test #'(discard-context + 1 2 3))
(syntax-test #'(discard-context . (+ 1 2 3)))
(syntax-test #'(discard-context keep-context + 1 2 3))

;; ----------------------------------------

(require (for-syntax scheme/struct-info))

(define-syntax (et-struct-info stx)
  (syntax-case stx ()
    [(_ id) #`(quote #,(extract-struct-info (syntax-local-value #'id)))]))

(let ([v (et-struct-info exn)])
  (test '(struct:exn make-exn exn? (exn-continuation-marks exn-message) (#f #f) #t) values v))

(let ([v (et-struct-info exn:break)])
  (test '(struct:exn:break make-exn:break exn:break? (exn:break-continuation exn-continuation-marks exn-message) (#f #f #f) exn) values v))

(let ([v (et-struct-info arity-at-least)])
  (test '(struct:arity-at-least make-arity-at-least arity-at-least? 
				(arity-at-least-value) (#f) #t) 
	values v))

(let ()
  (define-struct a (x y) #:mutable)
  (let ([v (et-struct-info a)])
    (test '(struct:a make-a a? (a-y a-x) (set-a-y! set-a-x!) #t) values v)
    (let ()
      (define-struct (b a) (z))
      (let ([v (et-struct-info b)])
	(test '(struct:b make-b b? (b-z a-y a-x) (#f set-a-y! set-a-x!) a) values v)))
    (let ()
      (define-struct (b exn) (z) #:mutable)
      (let ([v (et-struct-info b)])
	(test '(struct:b make-b b? (b-z exn-continuation-marks exn-message) (set-b-z! #f #f) exn) values v)))))
    
;; ----------------------------------------

(let () 
  (define-syntax (goo stx) 
    (syntax-case stx () 
      [(_ foo) #'(define-syntax (foo stx) (syntax-case stx () [(_ x) #'(define x 120)]))]))
  (goo foo)
  (foo x)
  (test 120 'intdef x))

(let-syntax ([goo (lambda (stx) #'(begin (define z 131) (test 131 'intdef z)))])
  (let-syntax ([y (lambda (stx) #'goo)])
    (let () 
      (define-syntax (goo stx) 
	(syntax-case stx () 
	  [(_ foo) #'(define-syntax (foo stx) (syntax-case stx () [(_ x) #'(define x 121)]))]))
      (goo foo)
      (foo x)
      y
      (test 121 'intdef x))))

(syntax-test #'(let ()
		 (define-syntax goo 10)
		 (define goo 10)
		 12))

(test 128 apply (lambda ()
                  (let-syntax ([ohno (lambda (stx) #'(define z -10))])
                    (let ()
                      (define ohno 128)
                      ohno
                      (define-syntax (goo stx) #'ohno)
                      ohno)))
      null)

(define-syntax (def-it stx)
  (syntax-case stx ()
    [(_ eid id) 
     #'(define-syntax eid #'id)]))

(define-syntax (get-it stx)
  (syntax-case stx ()
    [(_ id eid) 
     #`(define id #,(syntax-local-value #'eid))]))

(let ()
  (define x1 90)
  (def-it y1 x1)
  (get-it z1 y1)
  (test 90 'intdef z1))

(let ()
  (define-struct a (b c))
  (test 2 'intdef (a-c (make-a 1 2))))

(let ()
  (define-struct a (b c))
  (let ()
    (define-struct (d a) (e))
    (test 3 'intdef (d-e (make-d 1 2 3)))))

(let ()
  (define-struct a (b c))
  (define-struct (d a) (e))
  (test 3 'intdef (d-e (make-d 1 2 3))))

;; ----------------------------------------

(test 10 'vector-pattern (syntax-case #() () [#() 10]))
(test 'b 'vector-pattern (syntax-case #(a b c) () [#(x y z) (syntax-e #'y)]))

;; ----------------------------------------

(require (only-in mzlib/etc begin-with-definitions))

(define-syntax (def stx)
  (syntax-case stx ()
    [(_ id)
     (with-syntax ([x:id (datum->syntax #'id 'x)])
       #'(begin
           (define x:id 50)
           (define-syntax id #'x:id)))]))
(define-syntax (look stx)
  (syntax-case stx ()
    [(_ id) (syntax-local-value #'id)]))

(test 50 'look
      (let ()
        (def foo)
        (look foo)))

(test 50 'look
      (begin-with-definitions
       (def foo)
       (look foo)))

(test #t 'bwd-struct
      (let ()
        (begin-with-definitions
         (define-struct a (x y))
         (define-struct (b a) (z))
         (b? (make-b 1 2 3)))))

(test 5 'intdef
      (let ()
        (define-syntax foo
          (syntax-rules ()
            [(_ id) (begin
                      (define x 5)
                      (define id x))]))
        (foo x)
        x))

(test 6 'intdef-values
      (let ()
        (define-syntax foo
          (syntax-rules ()
            [(_ id) (define-values (x id) 
                      (values 6 (lambda () x)))]))
        (foo x)
        (x)))

(test 75 'bwd
      (begin-with-definitions
       (define-syntax foo
         (syntax-rules ()
           [(_ id) (begin
                     (define x 75)
                     (define id x))]))
       (foo x)
       x))

;; ----------------------------------------

(define-syntax (bind stx)
  (syntax-case stx ()
    [(_ handle def)
     (let ([def-ctx (syntax-local-make-definition-context)]
           [ctx (cons (gensym 'intdef)
                      (let ([orig-ctx (syntax-local-context)])
                        (if (pair? orig-ctx)
                            orig-ctx
                            null)))]
           [kernel-forms (list #'define-values)])
       (let ([def (local-expand #'def ctx kernel-forms def-ctx)])
         (syntax-case def ()
           [(define-values (id) rhs)
            (begin
              (syntax-local-bind-syntaxes (list #'id) #f def-ctx)
              (internal-definition-context-seal def-ctx)
              #'(begin
                  (define-values (id) rhs)
                  (define-syntax handle (quote-syntax id))))]
           [_ (error "no")])))]))

(define-syntax (nab stx)
  (syntax-case stx ()
    [(_ handle)
     (syntax-local-value #'handle)]))

(let ()
  (bind h (define q 5))
  (define q 8)
  (nab h))

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(module rename-transformer-tests scheme/base
  (require (for-syntax scheme/base))

  (define x 12)
  (define-syntax bar (let ([x 10])
                       (make-rename-transformer #'x)))
  (define-syntax foo (make-rename-transformer #'x))
  (list foo
        (identifier-binding #'foo)
        (free-identifier=? #'x #'foo))
  (identifier-binding #'bar)

  (begin-for-syntax 
   (define-struct rt (id)
     #:property prop:rename-transformer 0
     #:omit-define-syntaxes))

  (let-syntax ([q (make-rt #'x)])
    (list q
          (identifier-binding #'q)
          (free-identifier=? #'q #'x)))

  (let ([w 11])
    (letrec-syntax ([q (let ()
                         (define-struct rt ()
                           #:property prop:rename-transformer #'w)
                         (make-rt))])
      (list q
            (identifier-binding #'q)
            (free-identifier=? #'q #'w))))

  (letrec-syntax ([n (make-rename-transformer #'glob)])
    (list (identifier-binding #'n)
          (free-identifier=? #'n #'glob)))

  (letrec-syntax ([i (make-rename-transformer #'glob)])
    (letrec-syntax ([n (make-rename-transformer (syntax-property #'i 'not-free-identifier=? #f))])
      (list (identifier-binding #'n)
            (free-identifier=? #'n #'glob)))))

(let ([accum null])
  (parameterize ([current-print (lambda (v)
                                  (set! accum (cons (let loop ([v v])
                                                      (cond
                                                       [(module-path-index? v) 'mpi]
                                                       [(pair? v) (cons (loop (car v))
                                                                        (loop (cdr v)))]
                                                       [else v]))
                                                    accum)))])
    (dynamic-require ''rename-transformer-tests #f))
  (test '((#f #t) 
          (#f #t)
          (11 lexical #t)
          (12 (mpi x mpi x 0 0 0) #t)
          lexical
          (12 (mpi x mpi x 0 0 0) #t))
        values accum))

(module rename-transformer-tests:m scheme/base
  (require (for-syntax scheme/base))
  (define-syntax x 1)
  (define-syntax x* (make-rename-transformer #'x))
  (define-syntax x** (make-rename-transformer (syntax-property #'x 'not-free-identifier=? #t)))
  (define-syntax (get stx)
    (syntax-case stx ()
      [(_ i)
       #`#,(free-identifier=? #'i #'x)]))
  (provide get x* x**))

(module rename-transformer-tests:n scheme
  (require 'rename-transformer-tests:m)
  (provide go)
  (define (go)
    (list (get x*) (get x**))))

(test '(#t #f) (dynamic-require ''rename-transformer-tests:n 'go))

;; ----------------------------------------

(report-errs)
