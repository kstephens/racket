#lang racket/base

;; Foreign Racket interface
(require '#%foreign setup/dirs racket/unsafe/ops
         (for-syntax racket/base racket/list syntax/stx
                     racket/struct-info))

(provide ctype-sizeof ctype-alignof compiler-sizeof
         malloc free end-stubborn-change
         cpointer? ptr-equal? ptr-add ptr-ref ptr-set! (protect-out cast)
         ptr-offset ptr-add! offset-ptr? set-ptr-offset!
         vector->cpointer flvector->cpointer saved-errno lookup-errno
         ctype? make-ctype make-cstruct-type make-sized-byte-string ctype->layout
         _void _int8 _uint8 _int16 _uint16 _int32 _uint32 _int64 _uint64
         _fixint _ufixint _fixnum _ufixnum
         _float _double _double*
         _bool _pointer _gcpointer _scheme (rename-out [_scheme _racket]) _fpointer function-ptr
         memcpy memmove memset
         malloc-immobile-cell free-immobile-cell)

(define-syntax define*
  (syntax-rules ()
    [(_ (name . args) body ...)
     (begin (provide name) (define (name . args) body ...))]
    [(_ name expr)
     (begin (provide name) (define name expr))]))

;; ----------------------------------------------------------------------------
;; C integer types

(define* _sint8  _int8)
(define* _sint16 _int16)
(define* _sint32 _int32)
(define* _sint64 _int64)

;; _byte etc is a convenient name for _uint8 & _sint8
;; (_byte is unsigned)
(define* _byte  _uint8)
(define* _ubyte _uint8)
(define* _sbyte _int8)

;; _word etc is a convenient name for _uint16 & _sint16
;; (_word is unsigned)
(define* _word  _uint16)
(define* _uword _uint16)
(define* _sword _int16)

;; _short etc is a convenient name for whatever is the compiler's `short'
;; (_short is signed)
(provide _short _ushort _sshort)
(define-values (_short _ushort _sshort)
  (case (compiler-sizeof 'short)
    [(2) (values _int16 _uint16 _int16)]
    [(4) (values _int32 _uint32 _int32)]
    [else (error 'foreign "internal error: bad compiler size for `short'")]))

;; _int etc is a convenient name for whatever is the compiler's `int'
;; (_int is signed)
(provide _int _uint _sint)
(define-values (_int _uint _sint)
  (case (compiler-sizeof 'int)
    [(2) (values _int16 _uint16 _int16)]
    [(4) (values _int32 _uint32 _int32)]
    [(8) (values _int64 _uint64 _int64)]
    [else (error 'foreign "internal error: bad compiler size for `int'")]))

;; _long etc is a convenient name for whatever is the compiler's `long'
;; (_long is signed)
(provide _long _ulong _slong)
(define-values (_long _ulong _slong)
  (case (compiler-sizeof 'long)
    [(4) (values _int32 _uint32 _int32)]
    [(8) (values _int64 _uint64 _int64)]
    [else (error 'foreign "internal error: bad compiler size for `long'")]))

;; _llong etc is a convenient name for whatever is the compiler's `long long'
;; (_llong is signed)
(provide _llong _ullong _sllong)
(define-values (_llong _ullong _sllong)
  (case (compiler-sizeof '(long long))
    [(4) (values _int32 _uint32 _int32)]
    [(8) (values _int64 _uint64 _int64)]
    [else (error 'foreign "internal error: bad compiler size for `llong'")]))

;; ----------------------------------------------------------------------------
;; Getting and setting library objects

(define lib-suffix (bytes->string/latin-1 (subbytes (system-type 'so-suffix) 1)))
(define lib-suffix-re (regexp (string-append "\\." lib-suffix "$")))
(define suffix-before-version? (not (equal? lib-suffix "dylib")))

(provide (protect-out (rename-out [get-ffi-lib ffi-lib]))
         ffi-lib? ffi-lib-name)
(define get-ffi-lib
  (case-lambda
   [(name) (get-ffi-lib name "")]
   [(name version/s)
    (cond
      [(not name) (ffi-lib name)] ; #f => NULL => open this executable
      [(not (or (string? name) (path? name)))
       (raise-type-error 'ffi-lib "library-name" name)]
      [else
       ;; A possible way that this might be misleading: say that there is a
       ;; "foo.so" file in the current directory, which refers to some
       ;; undefined symbol, trying to use this function with "foo.so" will try
       ;; a dlopen with "foo.so" which isn't found, then it tries a dlopen with
       ;; "/<curpath>/foo.so" which fails because of the undefined symbol, and
       ;; since all fails, it will use (ffi-lib "foo.so") to raise the original
       ;; file-not-found error.  This is because the dlopen doesn't provide a
       ;; way to distinguish different errors (only dlerror, but that's
       ;; unreliable).
       (let* ([versions (if (list? version/s) version/s (list version/s))]
              [versions (map (lambda (v)
                               (if (or (not v) (zero? (string-length v)))
                                 "" (string-append "." v)))
                             versions)]
              [fullpath (lambda (p) (path->complete-path (cleanse-path p)))]
              [absolute? (absolute-path? name)]
              [name0 (path->string (cleanse-path name))]     ; orig name
              [names (map (if (regexp-match lib-suffix-re name0) ; name+suffix
                            (lambda (v) (string-append name0 v))
                            (lambda (v) 
                              (if suffix-before-version?
                                  (string-append name0 "." lib-suffix v)
                                  (string-append name0 v "." lib-suffix))))
                          versions)]
              [ffi-lib*  (lambda (name) (ffi-lib name #t))])
         (or ;; try to look in our library paths first
             (and (not absolute?)
                  (ormap (lambda (dir)
                           ;; try good names first, then original
                           (or (ormap (lambda (name)
                                        (ffi-lib* (build-path dir name)))
                                      names)
                               (ffi-lib* (build-path dir name0))))
                         (get-lib-search-dirs)))
             ;; try a system search
             (ormap ffi-lib* names)    ; try good names first
             (ffi-lib* name0)          ; try original
             (ormap (lambda (name)     ; try relative paths
                      (and (file-exists? name) (ffi-lib* (fullpath name))))
                    names)
             (and (file-exists? name0) ; relative with original
                  (ffi-lib* (fullpath name0)))
             ;; give up: call ffi-lib so it will raise an error
             (ffi-lib (car names))))])]))

(define (get-ffi-lib-internal x)
  (if (ffi-lib? x) x (get-ffi-lib x)))

;; These internal functions provide the functionality to be used by
;; get-ffi-obj, set-ffi-obj! and define-c below
(define (ffi-get ffi-obj type)
  (ptr-ref ffi-obj type))
(define (ffi-set! ffi-obj type new)
  (let-values ([(new type) (get-lowlevel-object new type)])
    (hash-set! ffi-objects-ref-table ffi-obj new)
    (ptr-set! ffi-obj type new)))

;; This is better handled with `make-c-parameter'
(provide (protect-out ffi-obj-ref))
(define ffi-obj-ref
  (case-lambda
   [(name lib) (ffi-obj-ref name lib #f)]
   [(name lib failure)
    (let ([name (get-ffi-obj-name 'ffi-obj-ref name)]
          [lib  (get-ffi-lib-internal lib)])
      (with-handlers ([exn:fail:filesystem?
                       (lambda (e) (if failure (failure) (raise e)))])
        (ffi-obj name lib)))]))

;; get-ffi-obj is implemented as a syntax only to be able to propagate the
;; foreign name into the type syntax, which allows generated wrappers to have a
;; proper name.
(provide (protect-out get-ffi-obj))
(define get-ffi-obj*
  (case-lambda
   [(name lib type) (get-ffi-obj* name lib type #f)]
   [(name lib type failure)
    (let ([name (get-ffi-obj-name 'get-ffi-obj name)]
          [lib  (get-ffi-lib-internal lib)])
      (let-values ([(obj error?)
                    (with-handlers
                        ([exn:fail:filesystem?
                          (lambda (e)
                            (if failure (values (failure) #t) (raise e)))])
                      (values (ffi-obj name lib) #f))])
        (if error? obj (ffi-get obj type))))]))
(define-syntax (get-ffi-obj stx)
  (syntax-case stx ()
    [(_ name lib type)
     #`(get-ffi-obj* name lib #,(syntax-property #`type 'ffi-name #'name))]
    [(_ name lib type failure)
     #`(get-ffi-obj* name lib #,(syntax-property #`type 'ffi-name #'name)
                     failure)]
    [x (identifier? #'x) #'get-ffi-obj*]))

;; It is important to use the set-ffi-obj! wrapper because it takes care of
;; keeping a handle on the object -- otherwise, setting a callback hook will
;; crash when the Scheme function is gone.
(provide (protect-out set-ffi-obj!))
(define (set-ffi-obj! name lib type new)
  (ffi-set! (ffi-obj (get-ffi-obj-name 'set-ffi-obj! name)
                     (get-ffi-lib-internal lib))
            type new))

;; Combining the above two in a `define-c' special form which makes a Scheme
;; `binding', first a `parameter'-like constructor:
(provide (protect-out make-c-parameter))
(define (make-c-parameter name lib type)
  (let ([obj (ffi-obj (get-ffi-obj-name 'make-c-parameter name)
                      (get-ffi-lib-internal lib))])
    (case-lambda [()    (ffi-get  obj type)]
                 [(new) (ffi-set! obj type new)])))
;; Then the fake binding syntax, uses the defined identifier to name the
;; object:
(provide (protect-out define-c))
(define-syntax (define-c stx)
  (syntax-case stx ()
    [(_ var-name lib-name type-expr)
     (with-syntax ([(p) (generate-temporaries (list #'var-name))])
       (namespace-syntax-introduce
        #'(begin (define p (make-c-parameter 'var-name lib-name type-expr))
                 (define-syntax var-name
                   (syntax-id-rules (set!)
                     [(set! var val) (p val)]
                     [(var . xs) ((p) . xs)]
                     [var (p)])))))]))

;; Used to convert strings and symbols to a byte-string that names an object
(define (get-ffi-obj-name who objname)
  (cond [(bytes? objname) objname]
        [(symbol? objname) (get-ffi-obj-name who (symbol->string objname))]
        [(string? objname) (string->bytes/utf-8 objname)]
        [else (raise-type-error who "object-name" objname)]))

;; This table keeps references to values that are set in foreign libraries, to
;; avoid them being GCed.  See set-ffi-obj! above.
(define ffi-objects-ref-table (make-hasheq))

;; ----------------------------------------------------------------------------
;; Compile-time support for fun-expanders

(begin-for-syntax

  ;; The `_fun' macro tears its input apart and reassemble it using pieces from
  ;; custom function types (macros).  This whole deal needs some work to make
  ;; it play nicely with code certificates, so Matthew wrote the following
  ;; code.  The idea is to create a define-fun-syntax which makes the new
  ;; syntax transformer be an object that carries extra information, later used
  ;; by `expand-fun-syntax/fun'.

  (define fun-cert-key (gensym))

  ;; bug in begin-for-syntax (PR7104), see below
  (define foo!!! (make-parameter #f))
  (define (expand-fun-syntax/normal fun-stx stx)
    ((foo!!!) fun-stx stx))

  (define-values (make-fun-syntax fun-syntax?
                  fun-syntax-proc fun-syntax-certifier fun-syntax-name)
    (let-values ([(desc make pred? get set!)
                  (make-struct-type
                   'fun-syntax #f 3 0 #f '() (current-inspector)
                   expand-fun-syntax/normal)])
      (values make pred?
              (make-struct-field-accessor get 0 'proc)
              (make-struct-field-accessor get 1 'certifier)
              (make-struct-field-accessor get 2 'name))))

  ;; This is used to expand a fun-syntax in a _fun type context.
  (define (expand-fun-syntax/fun stx)
    (let loop ([stx stx])
      (define (do-expand id id?) ; id? == are we expanding an identifier?
        (define v           (syntax-local-value id (lambda () #f)))
        (define set!-trans? (set!-transformer? v))
        (define proc        (if set!-trans? (set!-transformer-procedure v) v))
        (if (and (fun-syntax? proc) (or (not id?) set!-trans?))
          ;; Do essentially the same thing that `local-expand' does.
          ;;  First, create an "introducer" to mark introduced identifiers:
          (let* ([introduce (make-syntax-introducer)]
                 [expanded
                  ;; Re-introduce mark related to expansion of `_fun':
                  (syntax-local-introduce
                   ;; Re-add mark specific to this expansion, cancelling
                   ;;  some marks applied before expanding (leaving only
                   ;;  introuced syntax marked)
                   (introduce
                    ;; Actually expand:
                    ((fun-syntax-proc proc)
                     ;; Add mark specific to this expansion:
                     (introduce
                      ;; Remove mark related to expansion of `_fun':
                      (syntax-local-introduce stx)))))])
            ;; Certify based on definition of expander, then loop
            ;;  to continue expanding:
            (loop ((fun-syntax-certifier proc)
                   expanded fun-cert-key introduce)))
          stx))
      (syntax-case stx ()
        [(id . rest) (identifier? #'id) (do-expand #'id #f)]
        [id          (identifier? #'id) (do-expand #'id #t)]
        [_else stx])))

  ;; Use module-or-top-identifier=? because we use keywords like `=' and want
  ;; to make it possible to play with it at the toplevel.
  (define id=? module-or-top-identifier=?)

  (define (split-by key args)
    (let loop ([args args] [r (list '())])
      (cond [(null? args) (reverse (map reverse r))]
            [(eq? key (car args)) (loop (cdr args) (cons '() r))]
            [else (loop (cdr args)
                        (cons (cons (car args) (car r)) (cdr r)))])))

  (define (add-renamer body from to)
    (with-syntax ([body body] [from from] [to to])
      #'(let-syntax ([to (syntax-id-rules ()
                           [(_?_ . _rest_) (from . _rest_)] [_?_ from])])
          body)))

  (define (custom-type->keys type err)
    (define stops (map (lambda (s) (datum->syntax type s #f))
                       '(#%app #%top #%datum)))
    ;; Expand `type' using expand-fun-syntax/fun
    (define orig (expand-fun-syntax/fun type))
    (define (with-arg x)
      (syntax-case* x (=>) id=?
        [(id => body) (identifier? #'id)
         ;; Extract #'body from its context, use a key it needs certification:
         (list (syntax-recertify #'id orig #f fun-cert-key)
	       (syntax-recertify #'body orig #f fun-cert-key))]
        [_else x]))
    (define (cert-id id)
      (syntax-recertify id orig #f fun-cert-key))
   (let ([keys '()])
     (define (setkey! key val . id?)
       (cond
         [(assq key keys)
          (err "bad expansion of custom type (two `~a:'s)" key type)]
         [(and (pair? id?) (car id?) (not (identifier? val)))
          (err "bad expansion of custom type (`~a:' expects an identifier)"
               key type)]
         [else (set! keys (cons (cons key val) keys))]))
     (let loop ([t orig])
       (define (next rest . args) (apply setkey! args) (loop rest))
       (syntax-case* t
           (type: expr: bind: 1st-arg: prev-arg: pre: post: keywords:)
           id=?
         [(type: t x ...)      (next #'(x ...) 'type #'t)]
         [(expr:     e  x ...) (next #'(x ...) 'expr #'e)]
         [(bind:     id x ...) (next #'(x ...) 'bind (cert-id #'id) #t)]
         [(1st-arg:  id x ...) (next #'(x ...) '1st  (cert-id #'id) #t)]
         [(prev-arg: id x ...) (next #'(x ...) 'prev (cert-id #'id) #t)]
         ;; in the following two cases pass along orig for recertifying
         [(pre:      p  x ...) (next #'(x ...) 'pre  (with-arg #'p))]
         [(post:     p  x ...) (next #'(x ...) 'post (with-arg #'p))]
         [(keywords: x ...)
          (let kloop ([ks '()] [xs #'(x ...)])
            (syntax-case xs ()
              [(k v x ...) (syntax-e #'k)
               (kloop (cons (cons (syntax-e #'k) #'v) ks) #'(x ...))]
              [_ (next xs 'keywords (reverse ks))]))]
         [() (and (pair? keys) keys)]
         [_else #f]))))

  ;; This is used for a normal expansion of fun-syntax, when not in a _fun type
  ;; context.
  ;; bug in begin-for-syntax (PR7104), see above
  ;;   should be (define (expand-fun-syntax/normal fun-stx stx) ...)
  (foo!!! (lambda (fun-stx stx)
    (define (err msg . sub)
      (apply raise-syntax-error (fun-syntax-name fun-stx) msg stx sub))
    (let ([keys (custom-type->keys stx err)])
      (define (getkey key) (cond [(assq key keys) => cdr] [else #f]))
      (define (notkey key)
        (when (getkey key)
          (err (format "this type must be used in a _fun expression (uses ~s)"
                       key))))
      (if keys
        (let ([type (getkey 'type)] [pre (getkey 'pre)] [post (getkey 'post)])
          (unless type
            (err "this type must be used in a _fun expression (#f type)"))
          (for-each notkey '(expr bind 1st prev keywords))
          (if (or pre post)
            ;; a type with pre/post blocks
            (let ([make-> (lambda (x what)
                            (cond [(not x) #'#f]
                                  [(and (list? x) (= 2 (length x))
                                        (identifier? (car x)))
                                   #`(lambda (#,(car x)) #,(cadr x))]
                                  [else #`(lambda (_)
                                            (error '#,(fun-syntax-name fun-stx)
                                                   "cannot be used to ~a"
                                                   #,what))]))])
              (with-syntax ([type type]
                            [scheme->c (make-> pre "send values to C")]
                            [c->scheme (make-> post "get values from C")])
                #'(make-ctype type scheme->c c->scheme)))
            ;; simple type
            type))
        ;; no keys => normal expansion
        ((fun-syntax-proc fun-stx) stx))))))

;; Use define-fun-syntax instead of define-syntax for forms that
;;  are to be expanded by `_fun':
(provide define-fun-syntax)
(define-syntax define-fun-syntax
  (syntax-rules ()
    [(_ id trans)
     (define-syntax id
       (let* ([xformer trans]
              [set!-trans? (set!-transformer? xformer)])
         (unless (or (and (procedure? xformer)
                          (procedure-arity-includes? xformer 1))
                     set!-trans?)
           (raise-type-error 'define-fun-syntax
                             "procedure (arity 1) or set!-transformer"
                             xformer))
         (let ([f (make-fun-syntax (if set!-trans?
                                     (set!-transformer-procedure xformer)
                                     xformer)
                                   ;; Capture definition-time certificates:
                                   (syntax-local-certifier)
                                   'id)])
           (if set!-trans? (make-set!-transformer f) f))))]))

;; ----------------------------------------------------------------------------
;; Function type

;; Creates a simple function type that can be used for callouts and callbacks,
;; optionally applying a wrapper function to modify the result primitive
;; (callouts) or the input procedure (callbacks).
(define* (_cprocedure itypes otype
                      #:abi        [abi     #f]
                      #:wrapper    [wrapper #f]
                      #:keep       [keep    #f]
                      #:atomic?    [atomic? #f]
                      #:save-errno [errno   #f])
  (_cprocedure* itypes otype abi wrapper keep atomic? errno))

;; for internal use
(define held-callbacks (make-weak-hasheq))
(define (_cprocedure* itypes otype abi wrapper keep atomic? errno)
  (define-syntax-rule (make-it wrap)
    (make-ctype _fpointer
      (lambda (x)
        (and x
             (let ([cb (ffi-callback (wrap x) itypes otype abi atomic?)])
               (cond [(eq? keep #t) (hash-set! held-callbacks x cb)]
                     [(box? keep)
                      (let ([x (unbox keep)])
                        (set-box! keep
                                  (if (or (null? x) (pair? x)) (cons cb x) cb)))]
                     [(procedure? keep) (keep cb)])
               cb)))
      (lambda (x) (and x (wrap (ffi-call x itypes otype abi errno))))))
  (if wrapper (make-it wrapper) (make-it begin)))

;; Syntax for the special _fun type:
;; (_fun [{(name ... [. name]) | name} [-> expr] ::]
;;       {type | (name : type [= expr]) | ([name :] type = expr)} ...
;;       -> {type | (name : type)}
;;       [-> expr])
;; Usage:
;; `{(name ...) | ...} ::' specify explicit wrapper function formal arguments
;;           `-> expr'     can be used instead of the last expr
;; `type'                  input type (implies input, but see type macros next)
;; `(name : type = expr)'  specify name and type, `= expr' means computed input
;; `-> type'               output type (possibly with name)
;; `-> expr'               specify different output, can use previous names
;; Also, see below for custom function types.

(provide ->) ; to signal better errors when trying to use this with contracts
(define-syntax ->
  (syntax-id-rules ()
    [_ (raise-syntax-error '-> "should be used only in a _fun context")]))

(provide _fun)
(define-for-syntax _fun-keywords
  `([#:abi ,#'#f] [#:keep ,#'#t] [#:atomic? ,#'#f] [#:save-errno ,#'#f]))
(define-syntax (_fun stx)
  (define (err msg . sub) (apply raise-syntax-error '_fun msg stx sub))
  (define xs     #f)
  (define inputs #f)
  (define output #f)
  (define bind   '())
  (define pre    '())
  (define post   '())
  (define input-names #f)
  (define output-type #f)
  (define output-expr #f)
  (define 1st-arg     #f)
  (define prev-arg    #f)
  (define (bind! x) (set! bind (append bind (list x))))
  (define (pre!  x) (set! pre  (append pre  (list x))))
  (define (post! x) (set! post (append post (list x))))
  (define-values (kwd-ref kwd-set!)
    (let ([ks '()])
      (values
       (lambda (k)
         (cond [(assq k ks) => cdr]
               [(assq k _fun-keywords) => cadr]
               [else (error '_fun "internal error: unknown keyword: ~e" k)]))
       (lambda (k-stx v [sub k-stx])
         (let ([k (if (syntax? k-stx) (syntax-e k-stx) k-stx)])
           (cond [(assq k ks)
                  (err (if (keyword? k-stx)
                         (format "indirectly duplicate ~s keyword" k-stx)
                         "duplicate keyword")
                       sub)]
                 [(assq k _fun-keywords) (set! ks (cons (cons k v) ks))]
                 [else (err "unknown keyword" sub)]))))))
  (define ((t-n-e clause) type name expr)
    (let ([keys (custom-type->keys type err)])
      (define (getkey key) (cond [(assq key keys) => cdr] [else #f]))
      (define (arg x . no-expr?)
        (define use-expr?
          (and (list? x) (= 2 (length x)) (identifier? (car x))))
        ;; when the current expr is not used with a (x => ...) form,
        ;; either check that no expression is given or just make it
        ;; disappear from the inputs.
        (unless use-expr?
          (if (and (pair? no-expr?) (car no-expr?) expr)
            (err "got an expression for a custom type that do not use it"
                 clause)
            (set! expr (void))))
        (set! x (if use-expr? (add-renamer (cadr x) name (car x)) x))
        (cond [(getkey '1st) =>
               (lambda (v)
                 (if 1st-arg
                   (set! x (add-renamer x 1st-arg v))
                   (err "got a custom type that wants 1st arg too early"
                        clause)))])
        (cond [(getkey 'prev) =>
               (lambda (v)
                 (if prev-arg
                   (set! x (add-renamer x prev-arg v))
                   (err "got a custom type that wants prev arg too early"
                        clause)))])
        x)
      (when keys
        (set! type (getkey 'type))
        (cond [(and (not expr) (getkey 'expr)) => (lambda (x) (set! expr x))])
        (cond [(getkey 'bind) => (lambda (x) (bind! #`[#,x #,name]))])
        (cond [(getkey 'pre ) => (lambda (x) (pre!  #`[#,name #,(arg x #t)]))])
        (cond [(getkey 'post) => (lambda (x) (post! #`[#,name #,(arg x)]))])
        (cond [(getkey 'keywords)
               => (lambda (ks)
                    (for ([k+v (in-list ks)])
                      (kwd-set! (car k+v) (cdr k+v) clause)))]))
      ;; turn a #f syntax to #f
      (set! type (and type (syntax-case type () [#f #f] [_ type])))
      (when type ; remember these for later usages
        (unless 1st-arg (set! 1st-arg name))
        (set! prev-arg name))
      (list type name expr)))
  (define (do-fun)
    ;; parse keywords
    (let loop ()
      (let ([k (and (pair? xs) (pair? (cdr xs)) (car xs))])
        (when (keyword? (syntax-e k))
          (kwd-set! k (cadr xs))
          (set! xs (cddr xs))
          (loop))))
    ;; parse known punctuation
    (set! xs (map (lambda (x)
                    (syntax-case* x (-> ::) id=? [:: '::] [-> '->] [_  x]))
                  xs))
    ;; parse "::"
    (let ([s (split-by ':: xs)])
      (case (length s)
        [(0) (err "something bad happened (::)")]
        [(1) (void)]
        [(2) (if (and (= 1 (length (car s))) (not (eq? '-> (caar s))))
               (begin (set! xs (cadr s)) (set! input-names (caar s)))
               (err "bad wrapper formals"))]
        [else (err "saw two or more instances of `::'")]))
    ;; parse "->"
    (let ([s (split-by '-> xs)])
      (case (length s)
        [(0) (err "something bad happened (->)")]
        [(1) (err "missing output type")]
        [(2 3) (set! inputs (car s))
               (case (length (cadr s))
                 [(1) (set! output-type (caadr s))]
                 [(0) (err "missing output type after `->'")]
                 [else (err "extraneous output type" (cadadr s))])
               (unless (null? (cddr s))
                 (case (length (caddr s))
                   [(1) (set! output-expr (caaddr s))]
                   [(0) (err "missing output expression after `->'")]
                   [else (err "extraneous output expression"
                              (cadr (caddr s)))]))]
        [else (err "saw three or more instances of `->'")]))
    (set! inputs
          (map (lambda (sub temp)
                 (let ([t-n-e (t-n-e sub)])
                   (syntax-case* sub (: =) id=?
                     [(name : type)        (t-n-e #'type #'name #f)]
                     [(type = expr)        (t-n-e #'type temp   #'expr)]
                     [(name : type = expr) (t-n-e #'type #'name #'expr)]
                     [type                 (t-n-e #'type temp   #f)])))
               inputs
               (generate-temporaries (map (lambda (x) 'tmp) inputs))))
    ;; when processing the output type, only the post code matters
    (set! pre! (lambda (x) #f))
    (set! output
          (let ([temp (car (generate-temporaries #'(ret)))]
                [t-n-e (t-n-e output-type)])
            (syntax-case* output-type (: =) id=?
              [(name : type) (t-n-e #'type #'name output-expr)]
              [(type = expr) (if output-expr
                               (err "extraneous output expression" #'expr)
                               (t-n-e #'type temp #'expr))]
              [(name : type = expr)
                             (if output-expr
                               (err "extraneous output expression" #'expr)
                               (t-n-e #'type #'name #'expr))]
              [type          (t-n-e #'type temp output-expr)])))
    (let ([make-cprocedure
           (lambda (wrapper)
             #`(_cprocedure* (list #,@(filter-map car inputs))
                             #,(car output)
                             #,(kwd-ref '#:abi)
                             #,wrapper
                             #,(kwd-ref '#:keep)
                             #,(kwd-ref '#:atomic?)
                             #,(kwd-ref '#:save-errno)))])
      (if (or (caddr output) input-names (ormap caddr inputs)
              (ormap (lambda (x) (not (car x))) inputs)
              (pair? bind) (pair? pre) (pair? post))
        (let* ([input-names
                (or input-names
                    (filter-map (lambda (i) (and (not (caddr i)) (cadr i)))
                                inputs))]
               [output-expr
                (let ([o (caddr output)])
                  (or (and (not (void? o)) o) (cadr output)))]
               [args
                (filter-map (lambda (i)
                              (and (caddr i)
                                   (not (void? (caddr i)))
                                   #`[#,(cadr i) #,(caddr i)]))
                            inputs)]
               [ffi-args
                (filter-map (lambda (x) (and (car x) (cadr x))) inputs)]
               ;; the actual wrapper body
               [body (quasisyntax/loc stx
                       (lambda #,input-names
                         (let* (#,@args
                                #,@bind
                                #,@pre
                                [#,(cadr output) (ffi #,@ffi-args)]
                                #,@post)
                           #,output-expr)))]
               ;; if there is a string 'ffi-name property, use it as a name
               [body (let ([n (cond [(syntax-property stx 'ffi-name)
                                     => syntax->datum]
                                    [else #f])])
                       (if (string? n)
                         (syntax-property
                          body 'inferred-name
                          (string->symbol (string-append "ffi-wrapper:" n)))
                         body))])
          (make-cprocedure #`(lambda (ffi) #,body)))
        (make-cprocedure #'#f))))
  (syntax-case stx ()
    [(_ x ...) (begin (set! xs (syntax->list #'(x ...))) (do-fun))]))

(define (function-ptr p fun-ctype)
  (if (or (cpointer? p) (procedure? p))
      (if (eq? (ctype->layout fun-ctype) 'fpointer)
           (if (procedure? p)
               ((ctype-scheme->c fun-ctype) p)
               ((ctype-c->scheme fun-ctype) p))
          (raise-type-error 'function-ptr "function ctype" fun-ctype))
      (raise-type-error 'function-ptr "cpointer" p)))

;; ----------------------------------------------------------------------------
;; String types

;; The internal _string type uses the native ucs-4 encoding, also providing a
;; utf-16 type
(provide _string/ucs-4 _string/utf-16)

;; 8-bit string encodings, #f is NULL
(define ((false-or-op op) x) (and x (op x)))
(define* _string/utf-8
  (make-ctype _bytes
    (false-or-op string->bytes/utf-8) (false-or-op bytes->string/utf-8)))
(define* _string/locale
  (make-ctype _bytes
    (false-or-op string->bytes/locale) (false-or-op bytes->string/locale)))
(define* _string/latin-1
  (make-ctype _bytes
    (false-or-op string->bytes/latin-1) (false-or-op bytes->string/latin-1)))

;; 8-bit string encodings, #f is NULL, can also use bytes and paths
(define ((any-string-op op) x)
  (cond [(not    x) x]
        [(bytes? x) x]
        [(path?  x) (path->bytes x)]
        [else (op x)]))
(define* _string*/utf-8
  (make-ctype _bytes
    (any-string-op string->bytes/utf-8) (false-or-op bytes->string/utf-8)))
(define* _string*/locale
  (make-ctype _bytes
    (any-string-op string->bytes/locale) (false-or-op bytes->string/locale)))
(define* _string*/latin-1
  (make-ctype _bytes
    (any-string-op string->bytes/latin-1) (false-or-op bytes->string/latin-1)))

;; A generic _string type that usually does the right thing via a parameter
(define* default-_string-type
  (make-parameter _string*/utf-8
    (lambda (x)
      (if (ctype? x)
        x (error 'default-_string-type "expecting a C type, got ~e" x)))))
;; The type looks like an identifier, but it's actually using the parameter
(provide _string)
(define-syntax _string
  (syntax-id-rules ()
    [(_ . xs) ((default-_string-type) . xs)]
    [_ (default-_string-type)]))

;; _symbol is defined in C, since it uses simple C strings
(provide _symbol)

(provide _path)
;; `file' type: path-expands a path string, provide _path too.
(define* _file (make-ctype _path cleanse-path #f))

;; `string/eof' type: converts an output #f (NULL) to an eof-object.
(define string-type->string/eof-type
  (let ([table (make-hasheq)])
    (lambda (string-type)
      (hash-ref table string-type
        (lambda ()
          (let ([new-type (make-ctype string-type
                            (lambda (x) (and (not (eof-object? x)) x))
                            (lambda (x) (or x eof)))])
            (hash-set! table string-type new-type)
            new-type))))))
(provide _string/eof _bytes/eof)
(define _bytes/eof
  (make-ctype _bytes
              (lambda (x) (and (not (eof-object? x)) x))
              (lambda (x) (or x eof))))
(define-syntax _string/eof ; make it a syntax so it depends on the _string type
  (syntax-id-rules ()
    [(_ . xs) ((string-type->string/eof-type _string) . xs)]
    [_ (string-type->string/eof-type _string)]))

;; ----------------------------------------------------------------------------
;; Utility types

;; Call this with a name (symbol) and a list of symbols, where a symbol can be
;; followed by a '= and an integer to have a similar effect of C's enum.
(define (_enum* name symbols . base?)
  (define basetype (if (pair? base?) (car base?) _ufixint))
  (define sym->int '())
  (define int->sym '())
  (define s->c
    (if name (string->symbol (format "enum:~a->int" name)) 'enum->int))
  (let loop ([i 0] [symbols symbols])
    (unless (null? symbols)
      (let-values ([(i rest)
                    (if (and (pair? (cdr symbols))
                             (eq? '= (cadr symbols))
                             (pair? (cddr symbols)))
                        (values (caddr symbols)
                                (cdddr symbols))
                        (values i
                                (cdr symbols)))])
        (set! sym->int (cons (cons (car symbols) i) sym->int))
        (set! int->sym (cons (cons i (car symbols)) int->sym))
        (loop (add1 i) rest))))
  (make-ctype basetype
    (lambda (x)
      (let ([a (assq x sym->int)])
        (if a
          (cdr a)
          (raise-type-error s->c (format "~a" (or name "enum")) x))))
    (lambda (x) (cond [(assq x int->sym) => cdr] [else #f]))))

;; Macro wrapper -- no need for a name
(provide _enum)
(define-syntax (_enum stx)
  (syntax-case stx ()
    [(_ syms)
     (with-syntax ([name (syntax-local-name)])
       #'(_enum* 'name syms))]
    [(_ syms basetype)
     (with-syntax ([name (syntax-local-name)])
       #'(_enum* 'name syms basetype))]
    [id (identifier? #'id)
     #'(lambda (syms . base?) (apply _enum* #f syms base?))]))

;; Call this with a name (symbol) and a list of (symbol int) or symbols like
;; the above with '= -- but the numbers have to be specified in some way.  The
;; generated type will convert a list of these symbols into the logical-or of
;; their values and back.
(define (_bitmask* name orig-symbols->integers . base?)
  (define basetype (if (pair? base?) (car base?) _uint))
  (define s->c
    (if name (string->symbol (format "bitmask:~a->int" name)) 'bitmask->int))
  (define symbols->integers
    (let loop ([s->i orig-symbols->integers])
      (cond
       [(null? s->i)
        null]
       [(and (pair? (cdr s->i)) (eq? '= (cadr s->i)) (pair? (cddr s->i)))
        (cons (list (car s->i) (caddr s->i))
              (loop (cdddr s->i)))]
       [(and (pair? (car s->i)) (pair? (cdar s->i)) (null? (cddar s->i))
             (symbol? (caar s->i)) (integer? (cadar s->i)))
        (cons (car s->i) (loop (cdr s->i)))]
       [else
        (error '_bitmask "bad spec in ~e" orig-symbols->integers)])))
  (make-ctype basetype
    (lambda (symbols)
      (if (null? symbols) ; probably common
        0
        (let loop ([xs (if (pair? symbols) symbols (list symbols))] [n 0])
          (cond [(null? xs) n]
                [(assq (car xs) symbols->integers) =>
                 (lambda (x) (loop (cdr xs) (bitwise-ior (cadr x) n)))]
                [else (raise-type-error s->c (format "~a" (or name "bitmask"))
                                        symbols)]))))
    (lambda (n)
      (if (zero? n) ; probably common
        '()
        (let loop ([s->i symbols->integers] [l '()])
          (if (null? s->i)
            (reverse l)
            (loop (cdr s->i)
                  (let ([i (cadar s->i)])
                    (if (and (not (= i 0)) (= i (bitwise-and i n)))
                      (cons (caar s->i) l)
                      l)))))))))

;; Macro wrapper -- no need for a name
(provide _bitmask)
(define-syntax (_bitmask stx)
  (syntax-case stx ()
    [(_ syms)
     (with-syntax ([name (syntax-local-name)])
       #'(_bitmask* 'name syms))]
    [(_ syms basetype)
     (with-syntax ([name (syntax-local-name)])
       #'(_bitmask* 'name syms basetype))]
    [id (identifier? #'id)
     #'(lambda (syms . base?) (apply _bitmask* #f syms base?))]))

;; ----------------------------------------------------------------------------
;; Custom function type macros

;; These macros get expanded by the _fun type.  They can expand to a form that
;; looks like (keyword: value ...), where the keyword is one of:
;; * `type:'     for the type that will be used,
;; * `expr:'     an expression that will always be used for these arguments, as
;;               if `= expr' is always given, when an expression is actually
;;               given in an argument specification, it supersedes this.
;; * `bind:'     for an additional binding that holds the initial value,
;; * `1st-arg:'  is used to name an identifier that will be bound to the value
;;               of the 1st foreign argument in pre/post chunks (good for
;;               common cases where the first argument has a special meaning,
;;               eg, for method calls),
;; * `prev-arg:' similar to 1st-arg: but for the previous argument,
;; * `pre:'      for a binding that will be inserted before the ffi call,
;; * `post:'     for a binding after the ffi call,
;; * `keywords:' specifying keywords to be used in the surrounding _fun
;;               (the keywords and values follow).
;; The pre: and post: bindings can be of the form (id => expr) to use the
;; existing value.  Note that if the pre: expression is not (id => expr), then
;; it means that there is no input for this argument.  Also note that if a
;; custom type is used as an output type of a function, then only the post:
;; code is used -- for example, this is useful for foreign functions that
;; allocate a memory block and return it to the user.  The resulting wrapper
;; looks like:
;;   (let* (...bindings for arguments...
;;          ...bindings for bind: identifiers...
;;          ...bindings for pre-code...
;;          (ret-name ffi-call)
;;          ...bindings for post-code...)
;;     return-expression)
;;
;; Finally, the code in a custom-function macro needs special treatment when it
;; comes to dealing with code certificates, so instead of using
;; `define-syntax', you should use `define-fun-syntax' (used in the same way).

;; _?
;; This is not a normal ffi type -- it is a marker for expressions that should
;; not be sent to the ffi function.  Use this to bind local values in a
;; computation that is part of an ffi wrapper interface.
(provide _?)
(define-fun-syntax _?
  (syntax-id-rules () [(_ . xs) ((type: #f) . xs)] [_ (type: #f)]))

;; (_ptr <mode> <type>)
;; This is for pointers, where mode indicates input or output pointers (or
;; both).  If the mode is `o' (output), then the wrapper will not get an
;; argument for it, instead it generates the matching argument.
(provide _ptr)
(define-fun-syntax _ptr
  (syntax-rules (i o io)
    [(_ i  t) (type: _pointer
               pre:  (x => (let ([p (malloc t)]) (ptr-set! p t x) p)))]
    [(_ o  t) (type: _pointer
               pre:  (malloc t)
               post: (x => (ptr-ref x t)))]
    [(_ io t) (type: _pointer
               pre:  (x => (let ([p (malloc t)]) (ptr-set! p t x) p))
               post: (x => (ptr-ref x t)))]))

;; (_box <type>)
;; This is similar to a (_ptr io <type>) argument, where the input is expected
;; to be a box, which is unboxed on entry and modified on exit.
(provide _box)
(define-fun-syntax _box
  (syntax-rules ()
    [(_ t) (type: _pointer
            bind: tmp ; need to save the box so we can get back to it
            pre:  (x => (let ([p (malloc t)]) (ptr-set! p t (unbox x)) p))
            post: (x => (begin (set-box! tmp (ptr-ref x t)) tmp)))]))

;; (_list <mode> <type> [<len>])
;; Similar to _ptr, except that it is used for converting lists to/from C
;; vectors.  The length is needed for output values where it is used in the
;; post code, and in the pre code of an output mode to allocate the block.  In
;; any case it can refer to a previous binding for the length of the list which
;; the C function will most likely require.
(provide _list)
(define-fun-syntax _list
  (syntax-rules (i o io)
    [(_ i  t  ) (type: _pointer
                 pre:  (x => (list->cblock x t)))]
    [(_ o  t n) (type: _pointer
                 pre:  (malloc n t)
                 post: (x => (cblock->list x t n)))]
    [(_ io t n) (type: _pointer
                 pre:  (x => (list->cblock x t))
                 post: (x => (cblock->list x t n)))]))

;; (_vector <mode> <type> [<len>])
;; Same as _list, except that it uses Scheme vectors.
(provide _vector)
(define-fun-syntax _vector
  (syntax-rules (i o io)
    [(_ i  t  ) (type: _pointer
                 pre:  (x => (vector->cblock x t)))]
    [(_ o  t n) (type: _pointer
                 pre:  (malloc n t)
                 post: (x => (cblock->vector x t n)))]
    [(_ io t n) (type: _pointer
                 pre:  (x => (vector->cblock x t))
                 post: (x => (cblock->vector x t n)))]))

;; _bytes or (_bytes o n) is for a memory block represented as a Scheme byte
;; string.  _bytes is just like a byte-string, and (_bytes o n) is for
;; pre-malloc of the string.  There is no need for other modes: i or io would
;; be just like _bytes since the string carries its size information (so there
;; is no real need for the `o', but it's there for consistency with the above
;; macros).
(provide (rename-out [_bytes* _bytes]))
(define-fun-syntax _bytes*
  (syntax-id-rules (o)
    [(_ o n) (type: _pointer
              pre:  (make-sized-byte-string (malloc n) n)
              ;; post is needed when this is used as a function output type
              post: (x => (make-sized-byte-string x n)))]
    [(_ . xs) (_bytes . xs)]
    [_ _bytes]))

;; ----------------------------------------------------------------------------
;; Safe raw vectors

(define-struct cvector (ptr type length))

(provide cvector? cvector-length cvector-type cvector-ptr
         ;; make-cvector* is a dangerous operation
         (protect-out (rename-out [make-cvector make-cvector*])))

(define _cvector* ; used only as input types
  (make-ctype _pointer cvector-ptr
    (lambda (x)
      (error '_cvector
             "cannot automatically convert a C pointer to a cvector"))))

;; (_cvector <mode> [<type> <len>]) | _cevector
;; Same as _list etc above, except that it uses C vectors.
(provide _cvector)
(define-fun-syntax _cvector
  (syntax-id-rules (i o io)
    [(_ i     ) _cvector*]
    [(_ o  t n) (type: _pointer ; needs to be a pointer, not a cvector*
                 pre:  (malloc n t)
                 post: (x => (make-cvector x t n)))]
    [(_ io    ) (type: _cvector*
                 bind: tmp
                 pre:  (x => (cvector-ptr x))
                 post: (x => tmp))]
    [(_ . xs)   (_cvector* . xs)]
    [_          _cvector*]))

(provide (rename-out [allocate-cvector make-cvector]))
(define (allocate-cvector type len)
  (make-cvector (if (zero? len) #f ; 0 => NULL
                    (malloc len type))
                type len))

(provide (rename-out [cvector-args cvector]))
(define (cvector-args type . args)
  (list->cvector args type))

(define* (cvector-ref v i)
  (if (and (exact-nonnegative-integer? i) (< i (cvector-length v)))
    (ptr-ref (cvector-ptr v) (cvector-type v) i)
    (error 'cvector-ref "bad index ~e for cvector bounds of 0..~e"
           i (sub1 (cvector-length v)))))

(define* (cvector-set! v i x)
  (if (and (exact-nonnegative-integer? i) (< i (cvector-length v)))
    (ptr-set! (cvector-ptr v) (cvector-type v) i x)
    (error 'cvector-ref "bad index ~e for cvector bounds of 0..~e"
           i (sub1 (cvector-length v)))))

(define* (cvector->list v)
  (cblock->list (cvector-ptr v) (cvector-type v) (cvector-length v)))

(define* (list->cvector l type)
  (make-cvector (list->cblock l type) type (length l)))

;; ----------------------------------------------------------------------------
;; SRFI-4 implementation

(define-syntax (srfi-4-define/provide stx)
  (syntax-case stx ()
    [(_ TAG type)
     (identifier? #'TAG)
     (let ([name (format "~avector" (syntax->datum #'TAG))])
       (define (id prefix suffix)
         (let* ([name (if prefix (string-append prefix name) name)]
                [name (if suffix (string-append name suffix) name)])
           (datum->syntax #'TAG (string->symbol name) #'TAG)))
       (with-syntax ([TAG?         (id "" "?")]
                     [TAG          (id "" "")]
                     [s:TAG        (id "s:" "")]
                     [make-TAG     (id "make-" "")]
                     [TAG-ptr      (id "" "-ptr")]
                     [TAG-length   (id "" "-length")]
                     [allocate-TAG (id "allocate-" "")]
                     [TAG*         (id "" "*")]
                     [list->TAG    (id "list->" "")]
                     [TAG->list    (id "" "->list")]
                     [TAG-ref      (id "" "-ref")]
                     [TAG-set!     (id "" "-set!")]
                     [TAG->cpointer (id "" "->cpointer")]
                     [_TAG         (id "_" "")]
                     [_TAG*        (id "_" "*")]
                     [TAGname      name]
                     [f64?         (if (eq? (syntax-e #'TAG) 'f64) #'#t #'#f)])
         #'(begin
             (define-struct TAG (ptr length))
             (provide TAG? TAG-length (rename-out [TAG s:TAG]))
             (provide (rename-out [allocate-TAG make-TAG]))
             (define (allocate-TAG n . init)
               (let* ([p (if (eq? n 0) #f (malloc n type))]
                      [v (make-TAG p n)])
                 (when (and p (pair? init))
                   (let ([init (car init)])
                     (let loop ([i (sub1 n)])
                       (unless (< i 0)
                         (ptr-set! p type i init)
                         (loop (sub1 i))))))
                 v))
             (provide (rename-out [TAG* TAG]))
             (define (TAG* . vals)
               (list->TAG vals))
             (define* (TAG-ref v i)
               (if (TAG? v)
                   (if (and (exact-nonnegative-integer? i) (< i (TAG-length v)))
                       (if f64? ;; use JIT-inlined operation
                           (unsafe-f64vector-ref v i)
                           (ptr-ref (TAG-ptr v) type i))
                       (error 'TAG-ref "bad index ~e for ~a bounds of 0..~e"
                              i 'TAG (sub1 (TAG-length v))))
                   (raise-type-error 'TAG-ref TAGname v)))
             (define* (TAG-set! v i x)
               (if (TAG? v)
                   (if (and (exact-nonnegative-integer? i) (< i (TAG-length v)))
                       (if (and f64? ;; use JIT-inlined operation
                                (inexact-real? x))
                           (unsafe-f64vector-set! v i x)
                           (ptr-set! (TAG-ptr v) type i x))
                       (error 'TAG-set! "bad index ~e for ~a bounds of 0..~e"
                              i 'TAG (sub1 (TAG-length v))))
                   (raise-type-error 'TAG-set! TAGname v)))
             (define* (TAG->list v)
               (if (TAG? v)
                   (cblock->list (TAG-ptr v) type (TAG-length v))
                   (raise-type-error 'TAG->list TAGname v)))
             (define* (list->TAG l)
               (make-TAG (list->cblock l type) (length l)))
             (define* (TAG->cpointer v)
               (if (TAG? v)
                   (TAG-ptr v)
                   (raise-type-error 'TAG->cpointer TAGname v)))
             ;; same as the _cvector implementation
             (provide _TAG)
             (define _TAG*
               (make-ctype _pointer TAG-ptr
                           (lambda (x)
                             (error
                              '_TAG
                              "cannot automatically convert a C pointer to a ~a"
                              TAGname))))
             (define-fun-syntax _TAG
               (syntax-id-rules (i o io)
                 [(_ i   ) _TAG*]
                 [(_ o  n) (type: _pointer
                                  pre:  (malloc n type)
                                  post: (x => (make-TAG x n)))]
                 [(_ io  ) (type: _cvector*
                                  bind: tmp
                                  pre:  (x => (TAG-ptr x))
                                  post: (x => tmp))]
                 [(_ . xs)   (_TAG* . xs)]
                 [_          _TAG*])))))]
    [(_ TAG type)
     (identifier? #'TAG)]))

;; check that the types that were used above have the proper sizes
(unless (= 4 (ctype-sizeof _float))
  (error 'foreign "internal error: float has a bad size (~s)"
         (ctype-sizeof _float)))
(unless (= 8 (ctype-sizeof _double*))
  (error 'foreign "internal error: double has a bad size (~s)"
         (ctype-sizeof _double*)))

(srfi-4-define/provide s8  _int8)
(srfi-4-define/provide s16 _int16)
(srfi-4-define/provide u16 _uint16)
(srfi-4-define/provide s32 _int32)
(srfi-4-define/provide u32 _uint32)
(srfi-4-define/provide s64 _int64)
(srfi-4-define/provide u64 _uint64)
(srfi-4-define/provide f32 _float)
(srfi-4-define/provide f64 _double*)

;; simply rename bytes* to implement the u8vector type
(provide (rename-out [bytes?       u8vector?      ]
                     [bytes-length u8vector-length]
                     [make-bytes   make-u8vector  ]
                     [bytes        u8vector       ]
                     [bytes-ref    u8vector-ref   ]
                     [bytes-set!   u8vector-set!  ]
                     [bytes->list  u8vector->list ]
                     [list->bytes  list->u8vector ]
                     [_bytes       _u8vector      ]))
;; additional `u8vector' bindings for srfi-66
(provide (rename-out [bytes-copy u8vector-copy] [bytes=? u8vector=?]))
(define* (u8vector-compare v1 v2)
  (cond [(bytes<? v1 v2) -1]
        [(bytes>? v1 v2)  1]
        [else             0]))
(define* (u8vector-copy! src src-start dest dest-start n)
  (bytes-copy! dest dest-start src src-start (+ src-start n)))

;; ----------------------------------------------------------------------------
;; Tagged pointers

;; Make these operations available for unsafe interfaces (they can be used to
;; grab a hidden tag value and break code).
(provide cpointer-tag set-cpointer-tag!
         cpointer-has-tag? cpointer-push-tag!)

;; Defined as syntax for efficiency, but can be used as procedures too.
(define-syntax (cpointer-has-tag? stx)
  (syntax-case stx ()
    [(_ cptr tag)
     #'(let ([ptag (cpointer-tag cptr)])
         (if (pair? ptag) (memq tag ptag) (eq? tag ptag)))]
    [id (identifier? #'id)
     #'(lambda (cptr tag) (cpointer-has-tag? cptr tag))]))
(define-syntax (cpointer-push-tag! stx)
  (syntax-case stx ()
    [(_ cptr tag)
     #'(let ([ptag (cpointer-tag cptr)])
         (set-cpointer-tag! cptr
           (cond [(not ptag) tag]
                 [(pair? ptag) (cons tag ptag)]
                 [else (list tag ptag)])))]
    [id (identifier? #'id)
     #'(lambda (cptr tag) (cpointer-push-tag! cptr tag))]))

(define (cpointer-maker nullable?)
  (case-lambda
   [(tag) ((cpointer-maker nullable?) tag #f #f #f)]
   [(tag ptr-type) ((cpointer-maker nullable?) tag ptr-type #f #f)]
   [(tag ptr-type scheme->c c->scheme)
    (let* ([tag->C (string->symbol (format "~a->C" tag))]
           [error-str (format "~a`~a' pointer"
                              (if nullable? "" "non-null ") tag)]
           [error* (lambda (p) (raise-type-error tag->C error-str p))])
      (define-syntax-rule (tag-or-error ptr t)
        (let ([p ptr])
          (if (cpointer? p)
            (if (cpointer-has-tag? p t) p (error* p))
            (error* p))))
      (define-syntax-rule (tag-or-error/null ptr t)
        (let ([p ptr])
          (if (cpointer? p)
            (and p (if (cpointer-has-tag? p t) p (error* p)))
            (error* p))))
      (make-ctype (or ptr-type _pointer)
        ;; bad hack: `if's outside the lambda for efficiency
        (if nullable?
          (if scheme->c
            (lambda (p) (tag-or-error/null (scheme->c p) tag))
            (lambda (p) (tag-or-error/null p tag)))
          (if scheme->c
            (lambda (p) (tag-or-error (scheme->c p) tag))
            (lambda (p) (tag-or-error p tag))))
        (if nullable?
          (if c->scheme
            (lambda (p) (when p (cpointer-push-tag! p tag)) (c->scheme p))
            (lambda (p) (when p (cpointer-push-tag! p tag)) p))
          (if c->scheme
            (lambda (p)
              (if p (cpointer-push-tag! p tag) (error* p))
              (c->scheme p))
            (lambda (p)
              (if p (cpointer-push-tag! p tag) (error* p))
              p)))))]))

;; This is a kind of a pointer that gets a specific tag when converted to
;; Scheme, and accepts only such tagged pointers when going to C.  An optional
;; `ptr-type' can be given to be used as the base pointer type, instead of
;; _pointer, `scheme->c' and `c->scheme' can be used for adding conversion
;; hooks.
(define* _cpointer (cpointer-maker #f))

;; Similar to the above, but can tolerate null pointers (#f).
(define* _cpointer/null (cpointer-maker #t))

(define (cast p from-type to-type)
  (unless (ctype? from-type)
    (raise-type-error 'cast "ctype" from-type))
  (unless (ctype? to-type)
    (raise-type-error 'cast "ctype" to-type))
  (unless (= (ctype-sizeof to-type)
             (ctype-sizeof from-type))
    (raise-mismatch-error 'cast
                          (format "representation sizes of from and to types differ: ~e and "
                                  (ctype-sizeof from-type))
                          (ctype-sizeof to-type)))
  (let ([p2 (malloc from-type)])
    (ptr-set! p2 from-type p)
    (ptr-ref p2 to-type)))

(define* (_or-null ctype)
  (let ([coretype (ctype-coretype ctype)])
    (unless (memq coretype '(pointer gcpointer fpointer))
      (raise-type-error '_or-null "ctype buit on pointer, gcpointer, or fpointer" ctype))
    (make-ctype
     (case coretype
       [(pointer) _pointer]
       [(gcpointer) _gcpointer]
       [(fpointer) _fpointer])
     (lambda (v) (and v (cast v _pointer _pointer)))
     (lambda (v) (and v (cast v _pointer ctype))))))

(define* (_gcable ctype)
  (unless (memq (ctype-coretype ctype) '(pointer gcpointer))
    (raise-type-error '_or-null "pointer ctype" ctype))
  (let loop ([ctype ctype])
     (if (eq? ctype 'pointer)
         _gcpointer
         (make-ctype
          (loop (ctype-basetype ctype))
          (ctype-scheme->c ctype)
          (ctype-c->scheme ctype)))))

(define (ctype-coretype c)
  (let loop ([c (ctype-basetype c)])
    (if (symbol? c)
        c
        (loop (ctype-basetype c)))))

;; A macro version of the above two functions, using the defined name for a tag
;; string, and defining a predicate too.  The name should look like `_foo', the
;; predicate will be `foo?', and the tag will be "foo".  In addition, `foo-tag'
;; is bound to the tag.  The optional `ptr-type', `scheme->c', and `c->scheme'
;; arguments are the same as those of `_cpointer'.  `_foo' will be bound to the
;; _cpointer type, and `_foo/null' to the _cpointer/null type.
(provide define-cpointer-type)
(define-syntax (define-cpointer-type stx)
  (syntax-case stx ()
    [(_ _TYPE) #'(define-cpointer-type _TYPE #f #f #f)]
    [(_ _TYPE ptr-type) #'(define-cpointer-type _TYPE ptr-type #f #f)]
    [(_ _TYPE ptr-type scheme->c c->scheme)
     (and (identifier? #'_TYPE)
          (regexp-match #rx"^_.+" (symbol->string (syntax-e #'_TYPE))))
     (let ([name (cadr (regexp-match #rx"^_(.+)$"
                                     (symbol->string (syntax-e #'_TYPE))))])
       (define (id . strings)
         (datum->syntax
          #'_TYPE (string->symbol (apply string-append strings)) #'_TYPE))
       (with-syntax ([name-string name]
                     [TYPE?      (id name "?")]
                     [TYPE-tag   (id name "-tag")]
                     [_TYPE/null (id "_" name "/null")])
         #'(define-values (_TYPE _TYPE/null TYPE? TYPE-tag)
             (let ([TYPE-tag name-string])
               (values (_cpointer      TYPE-tag ptr-type scheme->c c->scheme)
                       (_cpointer/null TYPE-tag ptr-type scheme->c c->scheme)
                       (lambda (x)
                         (and (cpointer? x) (cpointer-has-tag? x TYPE-tag)))
                       TYPE-tag)))))]))

;; ----------------------------------------------------------------------------
;; Struct wrappers

(define (compute-offsets types)
  (let loop ([ts types] [cur 0] [r '()])
    (if (null? ts)
      (reverse r)
      (let* ([algn (ctype-alignof (car ts))]
             [pos  (+ cur (modulo (- (modulo cur algn)) algn))])
        (loop (cdr ts)
              (+ pos (ctype-sizeof (car ts)))
              (cons pos r))))))

;; Simple structs: call this with a list of types, and get a type that marshals
;; C structs to/from Scheme lists.
(define* (_list-struct . types)
  (let ([stype   (make-cstruct-type types)]
        [offsets (compute-offsets types)]
        [len     (length types)])
    (make-ctype stype
      (lambda (vals)
        (unless (and (list vals) (= len (length vals)))
          (raise-type-error 'list-struct (format "list of ~a items" len) vals))
        (let ([block (malloc stype)])
          (for-each (lambda (type ofs val) (ptr-set! block type 'abs ofs val))
                    types offsets vals)
          block))
      (lambda (block)
        (map (lambda (type ofs) (ptr-ref block type 'abs ofs))
             types offsets)))))

;; (define-cstruct _foo ([slot type] ...))
;; or
;; (define-cstruct (_foo _super) ([slot type] ...))
;; defines a type called _foo for a C struct, with user-procedues: make-foo,
;; foo? foo-slot... and set-foo-slot!....  The `_' prefix is required.  Objects
;; of this new type are actually cpointers, with a type tag that is "foo" and
;; (possibly more if the first type is itself a cstruct type or if a super type
;; is given,) provided as foo-tag, and tags of pointers are checked before
;; attempting to use them (see define-cpointer-type above).  Note that since
;; structs are implemented as pointers, they can be used for a _pointer input
;; to a foreign function: their address will be used, to make this possible,
;; the corresponding cpointer type is defined as _foo-pointer.  If a super
;; cstruct type is given, the constructor function expects values for every
;; field of the super type as well as other fields that are specified, and a
;; slot named `super' can be used to extract this initial struct -- although
;; pointers to the new struct type can be used as pointers to the super struct
;; type.
(provide define-cstruct)
(define-syntax (define-cstruct stx)
  (define (make-syntax _TYPE-stx has-super? slot-names-stx slot-types-stx)
    (define name
      (cadr (regexp-match #rx"^_(.+)$" (symbol->string (syntax-e _TYPE-stx)))))
    (define slot-names (map (lambda (x) (symbol->string (syntax-e x)))
                            (syntax->list slot-names-stx)))
    (define 1st-type
      (let ([xs (syntax->list slot-types-stx)]) (and (pair? xs) (car xs))))
    (define (id . strings)
      (datum->syntax
       _TYPE-stx (string->symbol (apply string-append strings)) _TYPE-stx))
    (define (ids name-func)
      (map (lambda (s)
             (datum->syntax
              _TYPE-stx
              (string->symbol (apply string-append (name-func s)))
              _TYPE-stx))
           slot-names))
    (define (safe-id=? x y)
      (and (identifier? x) (identifier? y) (free-identifier=? x y)))
    (with-syntax
        ([has-super?           has-super?]
         [name-string          name]
         [struct-string        (format "struct:~a" name)]
         [(slot ...)           slot-names-stx]
         [(slot-type ...)      slot-types-stx]
         [TYPE                 (id name)]
         [_TYPE                _TYPE-stx]
         [_TYPE-pointer        (id "_"name"-pointer")]
         [_TYPE-pointer/null   (id "_"name"-pointer/null")]
         [_TYPE/null           (id "_"name"/null")]
         [_TYPE*               (id "_"name"*")]
         [TYPE?                (id name"?")]
         [make-TYPE            (id "make-"name)]
         [list->TYPE           (id "list->"name)]
         [list*->TYPE          (id "list*->"name)]
         [TYPE->list           (id name"->list")]
         [TYPE->list*          (id name"->list*")]
         [TYPE-tag             (id name"-tag")]
         [(stype ...)          (ids (lambda (s) `(,name"-",s"-type")))]
         [(TYPE-SLOT ...)      (ids (lambda (s) `(,name"-",s)))]
         [(set-TYPE-SLOT! ...) (ids (lambda (s) `("set-",name"-",s"!")))]
         [(offset ...) (generate-temporaries
                               (ids (lambda (s) `(,s"-offset"))))])
      (with-syntax ([get-super-info
                     ;; the 1st-type might be a pointer to this type
                     (if (or (safe-id=? 1st-type #'_TYPE-pointer/null)
                             (safe-id=? 1st-type #'_TYPE-pointer))
                       #'(values #f '() #f #f #f #f)
                       #`(cstruct-info #,1st-type
                           (lambda () (values #f '() #f #f #f #f))))])
        #'(begin
            (define-syntax TYPE
              (make-struct-info
               (lambda ()
                 (list #f ; no struct:
                       (quote-syntax make-TYPE)
                       (quote-syntax TYPE?)
                       (reverse (list (quote-syntax TYPE-SLOT) ...))
                       (reverse (list (quote-syntax set-TYPE-SLOT!) ...))
                       #t))))
            (define-values (_TYPE _TYPE-pointer _TYPE-pointer/null TYPE? TYPE-tag
                                  make-TYPE TYPE-SLOT ... set-TYPE-SLOT! ...
                                  list->TYPE list*->TYPE TYPE->list TYPE->list*)
              (let-values ([(super-pointer super-tags super-types super-offsets
                                           super->list* list*->super)
                            get-super-info])
                (define-cpointer-type _TYPE super-pointer)
                ;; these makes it possible to use recursive pointer definitions
                (define _TYPE-pointer      _TYPE)
                (define _TYPE-pointer/null _TYPE/null)
                (let*-values ([(stype ...)  (values slot-type ...)]
                              [(types)      (list stype ...)]
                              [(offsets)    (compute-offsets types)]
                              [(offset ...) (apply values offsets)])
                  (define all-tags (cons TYPE-tag super-tags))
                  (define _TYPE*
                    ;; c->scheme adjusts all tags
                    (let* ([cst (make-cstruct-type types)]
                           [t (_cpointer TYPE-tag cst)]
                           [c->s (ctype-c->scheme t)])
                      (make-ctype cst (ctype-scheme->c t)
                                  ;; hack: modify & reuse the procedure made by _cpointer
                                  (lambda (p)
                                    (if p (set-cpointer-tag! p all-tags) (c->s p))
                                    p))))
                  (define-values (all-types all-offsets)
                    (if (and has-super? super-types super-offsets)
                        (values (append super-types   (cdr types))
                                (append super-offsets (cdr offsets)))
                        (values types offsets)))
                  (define (TYPE-SLOT x)
                    (unless (TYPE? x)
                      (raise-type-error 'TYPE-SLOT struct-string x))
                    (ptr-ref x stype 'abs offset))
                  ...
                  (define (set-TYPE-SLOT! x slot)
                    (unless (TYPE? x)
                      (raise-type-error 'set-TYPE-SLOT! struct-string 0 x slot))
                    (ptr-set! x stype 'abs offset slot))
                  ...
                  (define make-TYPE
                    (if (and has-super? super-types super-offsets)
                        ;; init using all slots
                        (lambda vals
                          (if (= (length vals) (length all-types))
                              (let ([block (malloc _TYPE*)])
                                (set-cpointer-tag! block all-tags)
                                (for-each (lambda (type ofs value)
                                            (ptr-set! block type 'abs ofs value))
                                          all-types all-offsets vals)
                                block)
                              (error '_TYPE "expecting ~s values, got ~s: ~e"
                                     (length all-types) (length vals) vals)))
                        ;; normal initializer
                        (lambda (slot ...)
                          (let ([block (malloc _TYPE*)])
                            (set-cpointer-tag! block all-tags)
                            (ptr-set! block stype 'abs offset slot)
                            ...
                            block))))
                  (define (list->TYPE vals) (apply make-TYPE vals))
                  (define (list*->TYPE vals)
                    (cond
                     [(TYPE? vals) vals]
                     [(= (length vals) (length all-types))
                      (let ([block (malloc _TYPE*)])
                        (set-cpointer-tag! block all-tags)
                        (for-each
                         (lambda (type ofs value)
                           (let-values
                               ([(ptr tags types offsets T->list* list*->T)
                                 (cstruct-info
                                  type
                                  (lambda () (values #f '() #f #f #f #f)))])
                             (ptr-set! block type 'abs ofs
                                       (if list*->T (list*->T value) value))))
                         all-types all-offsets vals)
                        block)]
                     [else (error '_TYPE "expecting ~s values, got ~s: ~e"
                                  (length all-types) (length vals) vals)]))
                  (define (TYPE->list x)
                    (unless (TYPE? x)
                      (raise-type-error 'TYPE-list struct-string x))
                    (map (lambda (type ofs) (ptr-ref x type 'abs ofs))
                         all-types all-offsets))
                  (define (TYPE->list* x)
                    (unless (TYPE? x)
                      (raise-type-error 'TYPE-list struct-string x))
                    (map (lambda (type ofs)
                           (let-values
                               ([(v) (ptr-ref x type 'abs ofs)]
                                [(ptr tags types offsets T->list* list*->T)
                                 (cstruct-info
                                  type
                                  (lambda () (values #f '() #f #f #f #f)))])
                             (if T->list* (T->list* v) v)))
                         all-types all-offsets))
                  (cstruct-info
                   _TYPE* 'set!
                   _TYPE all-tags all-types all-offsets TYPE->list* list*->TYPE)
                  (values _TYPE* _TYPE-pointer _TYPE-pointer/null TYPE? TYPE-tag
                          make-TYPE TYPE-SLOT ... set-TYPE-SLOT! ...
                          list->TYPE list*->TYPE TYPE->list TYPE->list*))))))))
  (define (identifiers? stx)
    (andmap identifier? (syntax->list stx)))
  (define (_-identifier? id stx)
    (and (identifier? id)
         (or (regexp-match #rx"^_." (symbol->string (syntax-e id)))
             (raise-syntax-error #f "cstruct name must begin with a `_'"
                                 stx id))))
  (syntax-case stx ()
    [(_ _TYPE ([slot slot-type] ...))
     (and (_-identifier? #'_TYPE stx)
          (identifiers? #'(slot ...)))
     (make-syntax #'_TYPE #f #'(slot ...) #'(slot-type ...))]
    [(_ (_TYPE _SUPER) ([slot slot-type] ...))
     (and (_-identifier? #'_TYPE stx) (identifiers? #'(slot ...)))
     (with-syntax ([super (datum->syntax #'_TYPE 'super #'_TYPE)])
       (make-syntax #'_TYPE #t #'(super slot ...) #'(_SUPER slot-type ...)))]))

;; helper for the above: keep runtime information on structs
(define cstruct-info
  (let ([table (make-weak-hasheq)])
    (lambda (cstruct msg/fail-thunk . args)
      (cond [(eq? 'set! msg/fail-thunk)
             (hash-set! table cstruct (make-ephemeron cstruct args))]
            [(and cstruct ; might get a #f if there were no slots
                  (hash-ref table cstruct (lambda () #f)))
             => (lambda (xs)
                  (let ([v (ephemeron-value xs)])
                    (if v (apply values v) (msg/fail-thunk))))]
            [else (msg/fail-thunk)]))))

;; ----------------------------------------------------------------------------
;;

(define prim-synonyms
  #hasheq((double* . double)
          (fixint . long)
          (ufixint . ulong)
          (fixnum . long)
          (ufixnum . ulong)
          (path . bytes)
          (symbol . bytes)
          (scheme . pointer)))

(define (ctype->layout c)
  (let ([b (ctype-basetype c)])
    (cond
     [(ctype? b) (ctype->layout b)]
     [(list? b) (map ctype->layout b)]
     [else (hash-ref prim-synonyms b b)])))

;; ----------------------------------------------------------------------------
;; Misc utilities

;; Used by set-ffi-obj! to get the actual value so it can be kept around
(define (get-lowlevel-object x type)
  (let ([basetype (ctype-basetype type)])
    (if (ctype? basetype)
      (let ([s->c (ctype-scheme->c type)])
        (get-lowlevel-object (if s->c (s->c x) x) basetype))
      (values x type))))

;; Converting Scheme lists to/from C vectors (going back requires a length)
(define* (list->cblock l type)
  (if (null? l)
    #f ; null => NULL
    (let ([cblock (malloc (length l) type)])
      (let loop ([l l] [i 0])
        (unless (null? l)
          (ptr-set! cblock type i (car l))
          (loop (cdr l) (add1 i))))
      cblock)))
(provide (protect-out cblock->list))
(define (cblock->list cblock type len)
  (cond [(zero? len) '()]
        [(cpointer? cblock)
         (let loop ([i (sub1 len)] [r '()])
           (if (< i 0)
             r
             (loop (sub1 i) (cons (ptr-ref cblock type i) r))))]
        [else (error 'cblock->list
                     "expecting a non-void pointer, got ~s" cblock)]))

;; Converting Scheme vectors to/from C vectors
(define* (vector->cblock v type)
  (let ([len (vector-length v)])
    (if (zero? len)
      #f ; #() => NULL
      (let ([cblock (malloc len type)])
        (let loop ([i 0])
          (when (< i len)
            (ptr-set! cblock type i (vector-ref v i))
            (loop (add1 i))))
        cblock))))
(provide (protect-out cblock->vector))
(define (cblock->vector cblock type len)
  (cond [(zero? len) '#()]
        [(cpointer? cblock)
         (let ([v (make-vector len)])
           (let loop ([i (sub1 len)])
             (unless (< i 0)
               (vector-set! v i (ptr-ref cblock type i))
               (loop (sub1 i))))
           v)]
        [else (error 'cblock->vector
                     "expecting a non-void pointer, got ~s" cblock)]))

;; Useful for automatic definitions
;; If a provided regexp begins with a "^" or ends with a "$", then
;; `regexp-replace' is used, otherwise use `regexp-replace*'.
(define* (regexp-replaces x rs)
  (let loop ([str (if (bytes? x) (bytes->string/utf-8 x) (format "~a" x))]
             [rs rs])
    (if (null? rs)
      str
      (loop ((if (regexp-match #rx"^\\^|\\$$"
                               (if (regexp? (caar rs))
                                 (object-name (caar rs)) (caar rs)))
               regexp-replace regexp-replace*)
             (caar rs) str (cadar rs)) (cdr rs)))))

;; A facility for running finalizers using executors.  #%foreign has a C-based
;; version that uses finalizers, but that leads to calling Scheme from the GC
;; which is not a good idea.
(define killer-executor (make-will-executor))
(define killer-thread #f)

(define* (register-finalizer obj finalizer)
  (unless killer-thread
    (let ([priviledged-custodian ((get-ffi-obj 'scheme_make_custodian #f (_fun _pointer -> _scheme)) #f)])
      (set! killer-thread
            (parameterize ([current-custodian priviledged-custodian])
              (thread (lambda ()
                        (let loop () (will-execute killer-executor) (loop))))))))
  (will-register killer-executor obj finalizer))
