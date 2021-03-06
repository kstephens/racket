#lang scribble/doc
@(require "mz.ss"
          (for-syntax racket/base)
          scribble/scheme
	  (for-label racket/generator
                     racket/mpair))

@(define generator-eval
   (lambda ()
     (let ([the-eval (make-base-eval)])
       (the-eval '(require racket/generator))
       the-eval)))

@(define (info-on-seq where what)
   @margin-note{See @secref[where] for information on using @|what| as sequences.})

@title[#:tag "sequences"]{Sequences}

@guideintro["sequences"]{sequences}

A @deftech{sequence} encapsulates an ordered stream of values. The
elements of a sequence can be extracted with one of the @scheme[for]
syntactic forms or with the procedures returned by
@scheme[sequence-generate].

The sequence datatype overlaps with many other datatypes. Among
built-in datatypes, the sequence datatype includes the following:

@itemize[

 @item{strings (see @secref["strings"])}
           
 @item{byte strings (see @secref["bytestrings"])}

 @item{lists (see @secref["pairs"])}

 @item{mutable lists (see @secref["mpairs"])}

 @item{vectors (see @secref["vectors"])}

 @item{hash tables (see @secref["hashtables"])}

 @item{dictionaries (see @secref["dicts"])}

 @item{sets (see @secref["sets"])}

 @item{input ports (see @secref["ports"])}

]

In addition, @scheme[make-do-sequence] creates a sequence given a
thunk that returns procedures to implement a generator, and the
@scheme[prop:sequence] property can be associated with a structure
type.

For most sequence types, extracting elements from a sequence has no
side-effect on the original sequence value; for example, extracting the
sequence of elements from a list does not change the list. For other
sequence types, each extraction implies a side effect; for example,
extracting the sequence of bytes from a port cause the bytes to be
read from the port.

Individual elements of a sequence typically correspond to single
values, but an element may also correspond to multiple values. For
example, a hash table generates two values---a key and its value---for
each element in the sequence.

@section{Sequence Predicate and Constructors}

@defproc[(sequence? [v any/c]) boolean?]{ Return @scheme[#t] if
@scheme[v] can be used as a sequence, @scheme[#f] otherwise.}

@defthing[empty-seqn sequence?]{ A sequence with no elements. }

@defproc[(seqn->list [s sequence?]) list?]{ Returns a list whose
elements are the elements of the @scheme[s], which must be a one-valued sequence.
If @scheme[s] is infinite, this function does not terminate. }

@defproc[(seqn-cons [v any/c]
                    ...
                    [s sequence?])
         sequence?]{
Returns a sequence whose first element is @scheme[(values v ...)] and whose
remaining elements are the same as @scheme[s].
}
                   
@defproc[(seqn-first [s sequence?])
         (values any/c ...)]{
Returns the first element of @scheme[s].}

@defproc[(seqn-rest [s sequence?])
         sequence?]{
Returns a sequence equivalent to @scheme[s], except the first element is omitted.}
                   
@defproc[(seqn-length [s sequence?])
         exact-nonnegative-integer?]{
Returns the number of elements of @scheme[s]. If @scheme[s] is infinite, this
function does not terminate. }

@defproc[(seqn-ref [s sequence?] [i exact-nonnegative-integer?])
         (values any/c ...)]{
Returns the @scheme[i]th element of @scheme[s].}
                            
@defproc[(seqn-tail [s sequence?] [i exact-nonnegative-integer?])
         sequence?]{
Returns a sequence equivalent to @scheme[s], except the first @scheme[i] elements are omitted.}

@defproc[(seqn-append [s sequence?] ...)
         sequence?]{
Returns a sequence that contains all elements of each sequence in the order they appear in the original sequences. The
new sequence is constructed lazily. }
                   
@defproc[(seqn-map [f procedure?]
                   [s sequence?])
         sequence?]{
Returns a sequence that contains @scheme[f] applied to each element of @scheme[s]. The new sequence is constructed lazily. }
                                  
@defproc[(seqn-andmap [f (-> any/c ... boolean?)]
                      [s sequence?])
         boolean?]{
Returns @scheme[#t] if @scheme[f] returns a true result on every element of @scheme[s]. If @scheme[s] is infinite and @scheme[f] never
returns a false result, this function does not terminate. }
                                  
@defproc[(seqn-ormap [f (-> any/c ... boolean?)]
                     [s sequence?])
         boolean?]{
Returns @scheme[#t] if @scheme[f] returns a true result on some element of @scheme[s]. If @scheme[s] is infinite and @scheme[f] never
returns a true result, this function does not terminate. }

@defproc[(seqn-for-each [f (-> any/c ... any)]
                   [s sequence?])
         (void)]{
Applies @scheme[f] to each element of @scheme[s]. If @scheme[s] is infinite, this function does not terminate. }
                
@defproc[(seqn-fold [f (-> any/c any/c ... any/c)]
                    [i any/c]
                    [s sequence?])
         (void)]{
Folds @scheme[f] over each element of @scheme[s] with @scheme[i] as the initial accumulator. If @scheme[s] is infinite, this function does not terminate. }
                
@defproc[(seqn-filter [f (-> any/c ... boolean?)]
                      [s sequence?])
         sequence?]{
Returns a sequence whose elements are the elements of @scheme[s] for which @scheme[f] returns a true result. Although the new sequence is constructed
lazily, if @scheme[s] has an infinite number of elements where @scheme[f] returns a false result in between two elements where @scheme[f] returns a true result
then operations on this sequence will not terminate during that infinite sub-sequence. }
                                  
@defproc[(seqn-add-between [s sequence?] [e any/c])
         sequence?]{
Returns a sequence whose elements are the elements of @scheme[s] except in between each is @scheme[e]. The new sequence is constructed lazily. }
                   
@defproc[(seqn-count [f procedure?] [s sequence?])
         exact-nonnegative-integer?]{
Returns the number of elements in @scheme[s] for which @scheme[f] returns a true result. If @scheme[s] is infinite, this function does not terminate. }
                  
@defproc*[([(in-range [end number?]) sequence?]
           [(in-range [start number?] [end number?] [step number? 1]) sequence?])]{
Returns a sequence whose elements are numbers. The single-argument
case @scheme[(in-range end)] is equivalent to @scheme[(in-range 0 end
1)].  The first number in the sequence is @scheme[start], and each
successive element is generated by adding @scheme[step] to the
previous element. The sequence stops before an element that would be
greater or equal to @scheme[end] if @scheme[step] is non-negative, or
less or equal to @scheme[end] if @scheme[step] is negative.
@speed[in-range "number"]}

@defproc[(in-naturals [start exact-nonnegative-integer? 0]) sequence?]{
Returns an infinite sequence of exact integers starting with
@scheme[start], where each element is one more than the preceding
element. @speed[in-naturals "integer"]}

@defproc[(in-list [lst list?]) sequence?]{
Returns a sequence equivalent to @scheme[lst].
@info-on-seq["pairs" "lists"]
@speed[in-list "list"]}

@defproc[(in-mlist [mlst mlist?]) sequence?]{
Returns a sequence equivalent to @scheme[mlst].
@info-on-seq["mpairs" "mutable lists"]
@speed[in-mlist "mutable list"]}

@defproc[(in-vector [vec vector?]
                    [start exact-nonnegative-integer? 0] 
                    [stop (or/c exact-nonnegative-integer? #f) #f] 
                    [step (and/c exact-integer? (not/c zero?)) 1]) 
         sequence?]{

Returns a sequence equivalent to @scheme[vec] when no optional
arguments are supplied.

@info-on-seq["vectors" "vectors"]

The optional arguments @scheme[start], @scheme[stop], and
@scheme[step] are analogous to @scheme[in-range], except that a
@scheme[#f] value for @scheme[stop] is equivalent to
@scheme[(vector-length vec)]. That is, the first element in the
sequence is @scheme[(vector-ref vec start)], and each successive
element is generated by adding @scheme[step] to index of the previous
element. The sequence stops before an index that would be greater or
equal to @scheme[end] if @scheme[step] is non-negative, or less or
equal to @scheme[end] if @scheme[step] is negative.

If @scheme[start] is less than @scheme[stop] and @scheme[step] is
negative, then the @exnraise[exn:fail:contract:mismatch]. Similarly,
if @scheme[start] is more than @scheme[stop] and @scheme[step] is
positive, then the @exnraise[exn:fail:contract:mismatch]. The
@scheme[start] and @scheme[stop] values are @emph{not} checked against
the size of @scheme[vec], so access can fail when an element is
demanded from the sequence.

@speed[in-vector "vector"]}

@defproc[(in-string [str string?]
                    [start exact-nonnegative-integer? 0] 
                    [stop (or/c exact-nonnegative-integer? #f) #f] 
                    [step (and/c exact-integer? (not/c zero?)) 1])
         sequence?]{
Returns a sequence equivalent to @scheme[str] when no optional
arguments are supplied.

@info-on-seq["strings" "strings"]

The optional arguments @scheme[start], @scheme[stop], and
@scheme[step] are as in @scheme[in-vector].

@speed[in-string "string"]}

@defproc[(in-bytes [bstr bytes?]
                   [start exact-nonnegative-integer? 0] 
                   [stop (or/c exact-nonnegative-integer? #f) #f] 
                   [step (and/c exact-integer? (not/c zero?)) 1])
         sequence?]{
Returns a sequence equivalent to @scheme[bstr] when no optional
arguments are supplied.

@info-on-seq["bytestrings" "byte strings"]

The optional arguments @scheme[start], @scheme[stop], and
@scheme[step] are as in @scheme[in-vector].

@speed[in-bytes "byte string"]}

@defproc[(in-port [r (input-port? . -> . any/c) read] 
		  [in input-port? (current-input-port)])
	 sequence?]{
Returns a sequence whose elements are produced by calling @scheme[r]
on @scheme[in] until it produces @scheme[eof].}

@defproc[(in-input-port-bytes [in input-port?]) sequence?]{
Returns a sequence equivalent to @scheme[(in-port read-byte in)].}

@defproc[(in-input-port-chars [in input-port?]) sequence?]{ Returns a
sequence whose elements are read as characters form @scheme[in]
(equivalent to @scheme[(in-port read-char in)]).}

@defproc[(in-lines [in input-port? (current-input-port)]
                   [mode (or/c 'linefeed 'return 'return-linefeed 'any 'any-one) 'any])
         sequence?]{

Returns a sequence equivalent to @scheme[(in-port (lambda (p)
(read-line p mode)) in)]. Note that the default mode is @scheme['any],
whereas the default mode of @scheme[read-line] is
@scheme['linefeed]. }

@defproc[(in-bytes-lines [in input-port? (current-input-port)]
                         [mode (or/c 'linefeed 'return 'return-linefeed 'any 'any-one) 'any])
         sequence?]{

Returns a sequence equivalent to @scheme[(in-port (lambda (p)
(read-bytes-line p mode)) in)]. Note that the default mode is @scheme['any],
whereas the default mode of @scheme[read-bytes-line] is
@scheme['linefeed]. }
                   
@defproc[(in-hash [hash hash?]) sequence?]{
Returns a sequence equivalent to @scheme[hash].

@info-on-seq["hashtables" "hash tables"]}

@defproc[(in-hash-keys [hash hash?]) sequence?]{
Returns a sequence whose elements are the keys of @scheme[hash].}

@defproc[(in-hash-values [hash hash?]) sequence?]{
Returns a sequence whose elements are the values of @scheme[hash].}

@defproc[(in-hash-pairs [hash hash?]) sequence?]{
Returns a sequence whose elements are pairs, each containing a key and
its value from @scheme[hash] (as opposed to using @scheme[hash] directly
as a sequence to get the key and value as separate values for each
element).}

@defproc[(in-directory [dir (or/c #f path-string?) #f]) sequence?]{

Return a sequence that produces all of the paths for files,
directories, and links with @racket[dir]. If @racket[dir] is not
@racket[#f], then every produced path starts with @racket[dir] as its
prefix. If @racket[dir] is @racket[#f], then paths in and relative to
the current directory are produced.}

@defproc[(in-producer [producer procedure?] [stop any/c] [args any/c] ...)
         sequence?]{
Returns a sequence that contains values from sequential calls to
@scheme[producer].  @scheme[stop] identifies the value that marks the
end of the sequence --- this value is not included in the sequence.
@scheme[stop] can be a predicate or a value that is tested against the
results with @scheme[eq?].  Note that you must use a predicate function
if the stop value is itself a function, or if the @scheme[producer]
returns multiple values.}

@defproc[(in-value [v any/c]) sequence?]{
Returns a sequence that produces a single value: @scheme[v]. This form
is mostly useful for @scheme[let]-like bindings in forms such as
@scheme[for*/list].}

@defproc[(in-indexed [seq sequence?]) sequence?]{Returns a sequence
where each element has two values: the value produced by @scheme[seq],
and a non-negative exact integer starting with @scheme[0]. The
elements of @scheme[seq] must be single-valued.}

@defproc[(in-sequences [seq sequence?] ...) sequence?]{Returns a
sequence that is made of all input sequences, one after the other. The
elements of each @scheme[seq] must all have the same number of
values.}

@defproc[(in-cycle [seq sequence?] ...) sequence?]{Similar to
@scheme[in-sequences], but the sequences are repeated in an infinite
cycle.}

@defproc[(in-parallel [seq sequence?] ...) sequence?]{Returns a
sequence where each element has as many values as the number of
supplied @scheme[seq]s; the values, in order, are the values of each
@scheme[seq]. The elements of each @scheme[seq] must be
single-valued.}

@defproc[(stop-before [seq sequence?] [pred (any/c . -> . any)])
sequence?]{ Returns a sequence that contains the elements of
@scheme[seq] (which must be single-valued), but only until the last
element for which applying @scheme[pred] to the element produces
@scheme[#t], after which the sequence ends.}

@defproc[(stop-after [seq sequence?] [pred (any/c . -> . any)])
sequence?]{ Returns a sequence that contains the elements of
@scheme[seq] (which must be single-valued), but only until the element
(inclusive) for which applying @scheme[pred] to the element produces
@scheme[#t], after which the sequence ends.}

@defproc[(make-do-sequence [thunk (-> (values (any/c . -> . any)
                                              (any/c . -> . any/c)
                                              any/c
                                              (any/c . -> . any/c)
                                              (() () #:rest list? . ->* . any/c)
                                              ((any/c) () #:rest list? . ->* . any/c)))])
         sequence?]{

Returns a sequence whose elements are generated by the procedures and
initial value returned by the thunk. The generator is defined in terms
of a @defterm{position}, which is initialized to the third result of
the thunk, and the @defterm{element}, which may consist of multiple
values.

The @scheme[thunk] results define the generated elements as follows:

@itemize[

 @item{The first result is a @scheme[_pos->element] procedure that takes
       the current position and returns the value(s) for the current element.}

 @item{The second result is a @scheme[_next-pos] procedure that takes
       the current position and returns the next position.}

 @item{The third result is the initial position.}

 @item{The fourth result takes the current position and returns a true
       result if the sequence includes the value(s) for the current
       position, and false if the sequence should end instead of
       including the value(s).}

 @item{The fifth result is like the fourth result, but it takes the
       current element value(s) instead of the current position.}

 @item{The sixth result is like the fourth result, but it takes both
       the current position and the current element values(s) and
       determines a sequence end after the current element is already
       included in the sequence.}

]

Each of the procedures listed above is called only once per position.
Among the last three procedures, as soon as one of the procedures
returns @scheme[#f], the sequence ends, and none are called
again. Typically, one of the functions determines the end condition,
and the other two functions always return @scheme[#t].}

@defthing[prop:sequence struct-type-property?]{

Associates a procedure to a structure type that takes an instance of
the structure and returns a sequence. If @scheme[v] is an instance of
a structure type with this property, then @scheme[(sequence? v)]
produces @scheme[#t].

@let-syntax[([car (make-element-id-transformer (lambda (id) #'@schemeidfont{car}))])
 @examples[
 (define-struct train (car next)
   #:property prop:sequence (lambda (t)
                              (make-do-sequence 
                               (lambda ()
                                 (values train-car
                                         train-next
                                         t
                                         (lambda (t) t)
                                         (lambda (v) #t)
                                         (lambda (t v) #t))))))
 (for/list ([c (make-train 'engine
                           (make-train 'boxcar
                                       (make-train 'caboose
                                                   #f)))])
   c)
 ]]}

@section{Sequence Generators}

@defproc[(sequence-generate [seq sequence?]) (values (-> boolean?)
                                                     (-> any))]{
Returns two thunks to extract elements from the sequence. The first
returns @scheme[#t] if more values are available for the sequence. The
second returns the next element (which may be multiple values) from the
sequence; if no more elements are available, the
@exnraise[exn:fail:contract].}

@section{Iterator Generators}
@defmodule[racket/generator]
@defform[(generator () body ...)]{ Creates a function that returns a
value through @scheme[yield], each time it is invoked. When
the generator runs out of values to yield, the last value it computed
will be returned for future invocations of the generator. Generators
can be safely nested.

Note: The first form must be @scheme[()]. In the future, the
@scheme[()] position will hold argument names that are used for the
initial generator call.

@examples[#:eval (generator-eval)
(define g (generator ()
	    (let loop ([x '(a b c)])
	      (if (null? x)
		0
		(begin
		  (yield (car x))
		  (loop (cdr x)))))))
(g)
(g)
(g)
(g)
(g)
]

To use an existing generator as a sequence, you should use @scheme[in-producer]
with a stop-value known to the generator.

@examples[#:eval (generator-eval)
(define my-stop-value (gensym))
(define my-generator (generator ()
		       (let loop ([x '(a b c)])
			 (if (null? x)
			   my-stop-value
			   (begin
			     (yield (car x))
			     (loop (cdr x)))))))

(for/list ([i (in-producer my-generator my-stop-value)])
  i)
]}

@defform[(infinite-generator body ...)]{ Creates a function similar to
@scheme[generator] but when the last @scheme[body] is executed the function
will re-execute all the bodies in a loop.

@examples[#:eval (generator-eval)
(define welcome
  (infinite-generator
    (yield 'hello)
    (yield 'goodbye)))
(welcome)
(welcome)
(welcome)
(welcome)
]}

@defproc[(in-generator [expr any?] ...) sequence?]{ Returns a generator
that can be used as a sequence. The @scheme[in-generator] procedure takes care of the
case when @scheme[expr] stops producing values, so when the @scheme[expr]
completes, the generator will end.

@examples[#:eval (generator-eval)
(for/list ([i (in-generator 
		(let loop ([x '(a b c)])
		  (when (not (null? x))
		    (yield (car x))
		    (loop (cdr x)))))])
  i)
]}

@defform[(yield expr ...)]{ Saves the point of execution inside a generator
and returns a value. @scheme[yield] can accept any number of arguments and will
return them using @scheme[values].

Values can be passed back to the generator after invoking @scheme[yield] by passing
the arguments to the generator instance. Note that a value cannot be passed back
to the generator until after the first @scheme[yield] has been invoked.

@examples[#:eval (generator-eval)
(define my-generator (generator () (yield 1) (yield 2 3 4)))
(my-generator)
(my-generator)
]

@examples[#:eval (generator-eval)
(define pass-values-generator
  (generator ()
    (let* ([from-user (yield 2)]
           [from-user-again (yield (add1 from-user))])
      (yield from-user-again))))

(pass-values-generator)
(pass-values-generator 5)
(pass-values-generator 12)
]}

@defproc[(generator-state [g any?]) symbol?]{ Returns a symbol that describes the state
of the generator.

 @itemize[
   @item{@scheme['fresh] - The generator has been freshly created and has not
   been invoked yet. Values cannot be passed to a fresh generator.}
   @item{@scheme['suspended] - Control within the generator has been suspended due
   to a call to @scheme[yield]. The generator can be invoked.}
   @item{@scheme['running] - The generator is currently executing. This state can
   only be returned if @scheme[generator-state] is invoked inside the generator.}
   @item{@scheme['done] - The generator has executed its entire body and will not
   call @scheme[yield] anymore.}
 ]

@examples[#:eval (generator-eval)
(define my-generator (generator () (yield 1) (yield 2)))
(generator-state my-generator)
(my-generator)
(generator-state my-generator)
(my-generator)
(generator-state my-generator)
(my-generator)
(generator-state my-generator)

(define introspective-generator (generator () ((yield 1))))
(introspective-generator)
(introspective-generator 
 (lambda () (generator-state introspective-generator)))
(generator-state introspective-generator)
(introspective-generator)
]}

@defproc[(sequence->generator [s sequence?]) (-> any?)]{

Returns a generator that returns elements from the sequence, @scheme[s],
each time the generator is invoked.}

@defproc[(sequence->repeated-generator [s sequence?]) (-> any?)]{

Returns a generator that returns elements from the sequence, @scheme[s],
similar to @scheme[sequence->generator] but looping over the values in
the sequence when no more values are left.}
