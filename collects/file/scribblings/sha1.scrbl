#lang scribble/doc
@(require "common.ss"
          scribble/eval
          (for-label file/sha1))

@(define sha1-eval (make-base-eval))
@interaction-eval[#:eval sha1-eval (require file/sha1)]

@title[#:tag "sha1b"]{SHA1 Message Digest}

@defmodule[file/sha1]

See @racketmodname[openssl/sha1] for a faster implementation.

@defproc[(sha1 [in input-port]) string?]{

Returns a 40-character string that represents the SHA-1 hash (in
hexadecimal notation) of the content from @scheme[in], consuming all
of the input from @scheme[in] until an end-of-file.

The @scheme[sha1] function composes @scheme[bytes->hex-string] with
@racket[sha1-bytes].

@examples[
#:eval sha1-eval
(sha1 (open-input-bytes #"abc"))
]}

@defproc[(sha1-bytes [in input-port]) bytes?]{

Returns a 20-byte byte string that represents the SHA-1 hash of the
content from @scheme[in], consuming all of the input from @scheme[in]
until an end-of-file.

@examples[
#:eval sha1-eval
(sha1-bytes (open-input-bytes #"abc"))
]}

@defproc[(bytes->hex-string [bstr bytes?]) string?]{

Converts the given byte string to a string representation, where each
byte in @scheme[bstr] is converted to its two-digit hexadecimal
representation in the resulting string.}
