
(module wrap-typed-non-optimizing racket
  (provide (rename-out (module-begin #%module-begin)))
  (require (lib "include.ss"))
  (require (prefix-in ts: typed/scheme/base))
  (require typed/scheme/base)
  (define-syntax (module-begin stx)
    (let ([name (symbol->string (syntax-property stx 'enclosing-module-name))])
      #`(ts:#%module-begin
         (include #,(format "~a.rktl"
                            (substring name
                                       0
                                       (caar (regexp-match-positions
                                              #rx"-non-optimizing"
                                              name)))))))))