#lang scribble/doc
@(require scribble/manual
          (for-label scheme/base
                     compiler/xform
                     dynext/compile)
          "common.ss")

@(define (xflag str) (as-index (DFlag str)))
@(define (pxflag str) (as-index (DPFlag str)))

@title[#:tag "cc"]{Compiling and Linking C Extensions}

A @deftech{dynamic extension} is a shared library (a.k.a. DLL) that
extends Racket using the C API. An extension can be loaded explicitly
via @racket[load-extension], or it can be loaded implicitly through
@racket[require] or @racket[load/use-compiled] in place of a source
@racket[_file] when the extension is located at

@racketblock[
(build-path "compiled" "native" (system-library-subpath)
            (path-add-suffix _file (system-type 'so-suffix)))
]

relative to @racket[_file].

For information on writing extensions, see @other-manual[inside-doc].

Three @exec{raco ctool} modes help for building extensions:

@itemize[

 @item{@DFlag{cc} : Runs the host system's C compiler, automatically
       supplying flags to locate the Racket header files and to
       compile for inclusion in a shared library.}

 @item{@DFlag{ld} : Runs the host system's C linker, automatically
       supplying flags to locate and link to the Racket libraries
       and to generate a shared library.}

 @item{@DFlag{xform} : Transforms C code that is written without
       explicit GC-cooperation hooks to cooperate with Racket's 3m
       garbage collector; see @secref[#:doc inside-doc "overview"] in
       @other-manual[inside-doc].}

]

Compilation and linking build on the @racketmodname[dynext/compile]
and @racketmodname[dynext/link] libraries. The following @exec{raco ctool} flags
correspond to setting or accessing parameters for those libraries: @xflag{tool},
@xflag{compiler}, @xflag{ccf}, @xflag{ccf}, @xflag{ccf-clear},
@xflag{ccf-show}, @xflag{linker}, @pxflag{ldf}, @xflag{ldf},
@xflag{ldf-clear}, @xflag{ldf-show}, @pxflag{ldl}, @xflag{ldl-show},
@pxflag{cppf}, @pxflag{cppf} @pxflag{cppf-clear}, and @xflag{cppf-show}.

The @as-index{@DFlag{3m}} flag specifies that the extension is to be
loaded into the 3m variant of Racket. The @as-index{@DFlag{cgc}}
flag specifies that the extension is to be used with the CGC. The
default depends on @exec{raco}: @DFlag{3m} if @exec{raco} itself is running in
3m, @DFlag{cgc} if @exec{raco} itself is running in CGC.


@section[#:tag "xform-api"]{API for 3m Transformation}

@defmodule[compiler/xform]

@defproc[(xform [quiet? any/c]
                [input-file path-string?]
                [output-file path-string?]
                [include-dirs (listof path-string?)]
                [#:keep-lines? keep-lines? boolean? #f])
         any/c]{

Transforms C code that is written without explicit GC-cooperation
hooks to cooperate with Racket's 3m garbage collector; see
@secref[#:doc '(lib "scribblings/inside/inside.scrbl") "overview"] in
@other-manual['(lib "scribblings/inside/inside.scrbl")].

The arguments are as for @racket[compile-extension]; in addition
@racket[keep-lines?] can be @racket[#t] to generate GCC-style
annotations to connect the generated C code with the original source
locations.

The file generated by @racket[xform] can be compiled via
@racket[compile-extension].}

