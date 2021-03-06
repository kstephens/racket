#lang scribble/doc
@(require "mz.ss"
          "match-grammar.ss"
          racket/match)

@(define match-eval (make-base-eval))
@(interaction-eval #:eval match-eval (require racket/match))

@title[#:tag "match"]{Pattern Matching}

@guideintro["match"]{pattern matching}

The @racket[match] form and related forms support general pattern
matching on Racket values. See also @secref["regexp"] for information
on regular-expression matching on strings, bytes, and streams.

@note-lib[racket/match #:use-sources (racket/match)]

@defform/subs[(match val-expr clause ...)
              ([clause [pat expr ...+]
                       [pat (=> id) expr ...+]])]{

Finds the first @racket[pat] that matches the result of
@racket[val-expr], and evaluates the corresponding @racket[expr]s with
bindings introduced by @racket[pat] (if any). The last @racket[expr]
in the matching clause is evaluated in tail position with respect to
the @racket[match] expression.

The @racket[clause]s are tried in order to find a match. If no
@racket[clause] matches, then the @exnraise[exn:misc:match?].

An optional @racket[(=> id)] between a @racket[pat] and the
@racket[expr]s is bound to a @defterm{failure procedure} of zero
arguments.  If this procedure is invoked, it escapes back to the
pattern matching expression, and resumes the matching process as if
the pattern had failed to match.  The @racket[expr]s must not mutate
the object being matched before calling the failure procedure,
otherwise the behavior of matching is unpredictable.

The grammar of @racket[pat] is as follows, where non-italicized
identifiers are recognized symbolically (i.e., not by binding).

@|match-grammar|

In more detail, patterns match as follows:

@itemize[

 @item{@racket[_id], excluding the reserved names @racketidfont{_},
       @racketidfont{...}, @racketidfont{.._},
       @racketidfont{..}@racket[_k], and
       @racketidfont{..}@racket[_k] for non-negative integers
       @racket[_k] --- matches anything, and binds @racket[id] to the
       matching values. If an @racket[_id] is used multiple times
       within a pattern, the corresponding matches must be the same
       according to @racket[(match-equality-test)], except that
       instances of an @racket[_id] in different @racketidfont{or} and
       @racketidfont{not} sub-patterns are independent.

       @examples[
       #:eval match-eval
       (match '(1 2 3)
         [(list a b a) (list a b)]
         [(list a b c) (list c b a)])
       (match '(1 '(x y z) 1)
         [(list a b a) (list a b)]
         [(list a b c) (list c b a)])
       ]}

 @item{@racketidfont{_} --- matches anything, without binding any
       identifiers.

       @examples[
       #:eval match-eval
       (match '(1 2 3)
         [(list _ _ a) a])
       ]}

 @item{@racket[#t], @racket[#f], @racket[_string], @racket[_bytes],
       @racket[_number], @racket[_char], or @racket[(#,(racketidfont
       "quote") _datum)] --- matches an @racket[equal?] constant.

       @examples[
       #:eval match-eval
       (match "yes"
         ["no" #f]
         ["yes" #t])
       ]}

 @item{@racket[(#,(racketidfont "list") _lvp ...)] --- matches a list
       of elements. In the case of @racket[(#,(racketidfont "list")
       _pat ...)], the pattern matches a list with as many element as
       @racket[_pat]s, and each element must match the corresponding
       @racket[_pat]. In the more general case, each @racket[_lvp]
       corresponds to a ``spliced'' list of greedy matches.

       For spliced lists, @racketidfont{...} and @racketidfont{___}
       are synonyms for zero or more matches. The
       @racketidfont{..}@racket[_k] and @racketidfont{__}@racket[_k]
       forms are also synonyms, specifying @racket[_k] or more
       matches. Pattern variables that precede these splicing
       operators are bound to lists of matching forms.

       @examples[
       #:eval match-eval
       (match '(1 2 3)
         [(list a b c) (list c b a)])
       (match '(1 2 3)
         [(list 1 a ...) a])
       (match '(1 2 3)
         [(list 1 a ..3) a]
         [_ 'else])
       (match '(1 2 3 4)
         [(list 1 a ..3) a]
         [_ 'else])
       (match '(1 2 3 4 5)
         [(list 1 a ..3 5) a]
         [_ 'else])
       (match '(1 (2) (2) (2) 5)
         [(list 1 (list a) ..3 5) a]
         [_ 'else])
       ]}

 @item{@racket[(#,(racketidfont "list-rest") _lvp ... _pat)] ---
       similar to a @racketidfont{list} pattern, but the final
       @racket[_pat] matches the ``rest'' of the list after the last
       @racket[_lvp]. In fact, the matched value can be a non-list
       chain of pairs (i.e., an ``improper list'') if @racket[_pat]
       matches non-list values.

      @examples[
       #:eval match-eval
      (match '(1 2 3 . 4)
        [(list-rest a b c d) d])
      (match '(1 2 3 . 4)
        [(list-rest a ... d) (list a d)])
      ]}

 @item{@racket[(#,(racketidfont "list-no-order") _pat ...)] ---
       similar to a @racketidfont{list} pattern, but the elements to
       match each @racket[_pat] can appear in the list in any order.

       @examples[
       #:eval match-eval
       (match '(1 2 3)
         [(list-no-order 3 2 x) x])
       ]}

 @item{@racket[(#,(racketidfont "list-no-order") _pat ... _lvp)] ---
       generalizes @racketidfont{list-no-order} to allow a pattern
       that matches multiple list elements that are interspersed in
       any order with matches for the other patterns.

       @examples[
       #:eval match-eval
       (match '(1 2 3 4 5 6)
         [(list-no-order 6 2 y ...) y])
       ]}

 @item{@racket[(#,(racketidfont "vector") _lvp ...)] --- like a
       @racketidfont{list} pattern, but matching a vector.

       @examples[
       #:eval match-eval
       (match #(1 (2) (2) (2) 5)
         [(vector 1 (list a) ..3 5) a])
       ]}

 @item{@racket[(#,(racketidfont "hash-table") (_pat _pat) ...)] ---
       similar to @racketidfont{list-no-order}, but matching against
       hash table's key--value pairs.

       @examples[
       #:eval match-eval
       (match #hash(("a" . 1) ("b" . 2))
         [(hash-table ("b" b) ("a" a)) (list b a)])
       ]}

 @item{@racket[(#,(racketidfont "hash-table") (_pat _pat) ...+ _ooo)]
       --- Generalizes @racketidfont{hash-table} to support a final
       repeating pattern.

       @examples[
       #:eval match-eval
       (match #hash(("a" . 1) ("b" . 2))
         [(hash-table (key val) ...) key])
       ]}

 @item{@racket[(#,(racketidfont "cons") _pat1 _pat2)] --- matches a pair value.

       @examples[
       #:eval match-eval
       (match (cons 1 2)
         [(cons a b) (+ a b)])
       ]}

 @item{@racket[(#,(racketidfont "mcons") _pat1 _pat2)] --- matches a mutable pair value.

       @examples[
       #:eval match-eval
       (match (mcons 1 2)
         [(cons a b) 'immutable]
	 [(mcons a b) 'mutable])
       ]}

 @item{@racket[(#,(racketidfont "box") _pat)] --- matches a boxed value.

       @examples[
       #:eval match-eval
       (match #&1
         [(box a) a])
       ]}

 @item{@racket[(_struct-id _pat ...)] or
       @racket[(#,(racketidfont "struct") _struct-id (_pat ...))] ---
       matches an instance of a structure type names
       @racket[_struct-id], where each field in the instance matches
       the corresponding @racket[_pat]. See also @scheme[struct*].

       Usually, @racket[_struct-id] is defined with
       @racket[struct].  More generally, @racket[_struct-id]
       must be bound to expansion-time information for a structure
       type (see @secref["structinfo"]), where the information
       includes at least a predicate binding and field accessor
       bindings corresponding to the number of field
       @racket[_pat]s. In particular, a module import or a
       @racket[unit] import with a signature containing a
       @racket[struct] declaration can provide the structure type
       information.

       @defexamples[
       #:eval match-eval
       (define-struct tree (val left right))
       (match (make-tree 0 (make-tree 1 #f #f) #f)
         [(tree a (tree b  _ _) _) (list a b)])
       ]}

 @item{@racket[(#,(racketidfont "struct") _struct-id _)] ---
       matches any instance of @racket[_struct-id], without regard to
       contents of the fields of the instance.
       }

 @item{@racket[(#,(racketidfont "regexp") _rx-expr)] --- matches a
       string that matches the regexp pattern produced by
       @racket[_rx-expr]; see @secref["regexp"] for more information
       about regexps.

       @examples[
       #:eval match-eval
       (match "apple"
         [(regexp #rx"p+") 'yes]
         [_ 'no])
       (match "banana"
         [(regexp #rx"p+") 'yes]
         [_ 'no])
       ]}

 @item{@racket[(#,(racketidfont "regexp") _rx-expr _pat)] --- extends
       the @racketidfont{regexp} form to further constrain the match
       where the result of @racket[regexp-match] is matched against
       @racket[_pat].

       @examples[
       #:eval match-eval
       (match "apple"
         [(regexp #rx"p+(.)" (list _ "l")) 'yes]
         [_ 'no])
       (match "append"
         [(regexp #rx"p+(.)" (list _ "l")) 'yes]
         [_ 'no])
       ]}

 @item{@racket[(#,(racketidfont "pregexp") _rx-expr)] or
       @racket[(#,(racketidfont "regexp") _rx-expr _pat)] --- like the
       @racketidfont{regexp} patterns, but if @racket[_rx-expr]
       produces a string, it is converted to a pattern using
       @racket[pregexp] instead of @racket[regexp].}

 @item{@racket[(#,(racketidfont "and") _pat ...)] --- matches if all
       of the @racket[_pat]s match.  This pattern is often used as
       @racket[(#,(racketidfont "and") _id _pat)] to bind @racket[_id]
       to the entire value that matches @racket[pat].

       @examples[
       #:eval match-eval
       (match '(1 (2 3) 4)
        [(list _ (and a (list _ ...)) _) a])
       ]}

 @item{@racket[(#,(racketidfont "or") _pat ...)] --- matches if any of
       the @racket[_pat]s match. @bold{Beware}: the result expression
       can be duplicated once for each @racket[_pat]! Identifiers in
       @racket[_pat] are bound only in the corresponding copy of the
       result expression; in a module context, if the result
       expression refers to a binding, then that all @racket[_pat]s
       must include the binding.

       @examples[
       #:eval match-eval
       (match '(1 2)
        [(or (list a 1) (list a 2)) a])
       ]}

 @item{@racket[(#,(racketidfont "not") _pat ...)] --- matches when
       none of the @racket[_pat]s match, and binds no identifiers.

       @examples[
       #:eval match-eval
       (match '(1 2 3)
        [(list (not 4) ...) 'yes]
        [_ 'no])
       (match '(1 4 3)
        [(list (not 4) ...) 'yes]
        [_ 'no])
       ]}

 @item{@racket[(#,(racketidfont "app") _expr _pat)] --- applies
       @racket[_expr] to the value to be matched; the result of the
       application is matched againt @racket[_pat].

       @examples[
       #:eval match-eval
       (match '(1 2)
        [(app length 2) 'yes])
       ]}

 @item{@racket[(#,(racketidfont "?") _expr _pat ...)] --- applies
       @racket[_expr] to the value to be matched, and checks whether
       the result is a true value; the additional @racket[_pat]s must
       also match (i.e., @racketidfont{?} combines a predicate
       application and an @racketidfont{and} pattern).

       @examples[
       #:eval match-eval
       (match '(1 3 5)
        [(list (? odd?) ...) 'yes])
       ]}

  @item{@racket[(#,(racketidfont "quasiquote") _qp)] --- introduces a
        quasipattern, in which identifiers match symbols. Like the
        @racket[quasiquote] expression form, @racketidfont{unquote}
        and @racketidfont{unquote-splicing} escape back to normal
        patterns.
        
        @examples[
       #:eval match-eval
        (match '(1 2 3)
          [`(1 ,a ,(? odd? b)) (list a b)])
        ]}

 @item{@racket[_derived-pattern] --- matches a pattern defined by a
       macro extension via @racket[define-match-expander].}

]}

@; ----------------------------------------------------------------------

@section{Additional Matching Forms}

@defform/subs[(match* (val-expr ...+) clause* ...)
	      ([clause* [(pat ...+) expr ...+]
			[(pat ...+) (=> id) expr ...+]])]{
Matches a sequence of values against each clause in order, matching
only when all patterns in a clause match.  Each clause must have the
same number of patterns as the number of @racket[val-expr]s. 

@examples[#:eval match-eval
(match* (1 2 3)
 [(_ (? number?) x) (add1 x)])
]
}

@defform[(match-lambda clause ...)]{

Equivalent to @racket[(lambda (id) (match id clause ...))].
}

@defform[(match-lambda* clause ...)]{

Equivalent to @racket[(lambda lst (match lst clause ...))].
}

@defform[(match-let ([pat expr] ...) body ...+)]{

Generalizes @racket[let] to support pattern bindings. Each
@racket[expr] is matched against its corresponding @racket[pat] (the
match must succeed), and the bindings that @racket[pat] introduces are
visible in the @racket[body]s.

@examples[
#:eval match-eval
(match-let ([(list a b) '(1 2)]
            [(vector x ...) #(1 2 3 4)])
  (list b a x))
]}

@defform[(match-let* ([pat expr] ...) body ...+)]{

Like @racket[match-let], but generalizes @racket[let*], so that the
bindings of each @racket[pat] are available in each subsequent
@racket[expr].

@examples[
#:eval match-eval
(match-let* ([(list a b) '(#(1 2 3 4) 2)]
             [(vector x ...) a])
  x)
]}

@defform[(match-letrec ([pat expr] ...) body ...+)]{

Like @racket[match-let], but generalizes @racket[letrec].}


@defform[(match-define pat expr)]{

Defines the names bound by @racket[pat] to the values produced by
matching against the result of @racket[expr].

@examples[
#:eval match-eval
(match-define (list a b) '(1 2))
b
]}

@; ----------------------------------------

@defproc[(exn:misc:match? [v any/c]) boolean?]{
A predicate for the exception raised by in the case of a match failure.
}


@; ----------------------------------------

@section{Extending @racket[match]}

@defform*[((define-match-expander id proc-expr)
           (define-match-expander id proc-expr proc-expr))]{

Binds @racket[id] to a @deftech{match expander}.

The first @racket[proc-expr] subexpression must evaluate to a
 transformer that produces a @racket[_pat] for @racket[match].
 Whenever @racket[id] appears as the beginning of a pattern, this
 transformer is given, at expansion time, a syntax object
 corresponding to the entire pattern (including @racket[id]).  The
 pattern is the replaced with the result of the transformer.

A transformer produced by a second @racket[proc-expr] subexpression is
 used when @racket[id] is used in an expression context. Using the
 second @racket[proc-expr], @racket[id] can be given meaning both
 inside and outside patterns.}

@defparam[match-equality-test comp-proc (any/c any/c . -> . any)]{

A parameter that determines the comparison procedure used to check
whether multiple uses of an identifier match the ``same'' value. The
default is @racket[equal?].}

@; ----------------------------------------------------------------------

@section{Library Extensions}

@defform[(struct* struct-id ([field pat] ...))]{
 A @scheme[match] pattern form that matches an instance of a structure
 type named @racket[struct-id], where the field @racket[field] in the
 instance matches the corresponding @racket[pat].
                                                
 Any field of @racket[struct-id] may be omitted and they may occur in any order.
 
 @defexamples[
  #:eval match-eval
  (define-struct tree (val left right))
  (match (make-tree 0 (make-tree 1 #f #f) #f)
    [(struct* tree ([val a]
                    [left (struct* tree ([right #f] [val b]))]))
     (list a b)])
 ]
 }

@; ----------------------------------------------------------------------

@close-eval[match-eval]
