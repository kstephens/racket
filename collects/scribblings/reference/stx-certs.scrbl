#lang scribble/doc
@(require "mz.ss")

@title[#:tag "stxcerts"]{Syntax Certificates}

@guideintro["stx-certs"]{syntax certificates}

A @deftech{syntax certificate} combines a @tech{syntax mark} (see
@secref["transformer-model"]), a @tech{module path index} or symbol
module name (see @secref["modpathidx"]), an @tech{inspector} (see
@secref["modprotect"]), and an arbitrary key object. A certificate
is attached as either an @deftech{active certificate} or an
@deftech{inactive certificate}.

The @scheme[datum->syntax] procedure never transfers an @tech{active
certificate} from one syntax object to another. The
@scheme[syntax-recertify] procedure can be used to transfer a
certificate from one syntax object to another, but only if the
certificate's key is provided, or if a sufficiently powerful inspector
is provided. Thus, a certificate's inspector serves two roles: it
determines the certificate's power to grant access, and also allows
the certificate to be moved arbitrarily by anyone with a more powerful
inspector.

The expander generates a certificate when it applies a syntax
transformer. The @tech{syntax mark} in the certificate is fresh, the
certificate's module reference corresponds to the module that defined
the @tech{transformer binding}, the inspector is the inspector for the
module's declaration (see @secref["modprotect"]), and the key
object is hidden. (Applying the result of
@scheme[syntax-local-certifier] can introduce certificates with other
keys.) The certificate's mark is applied to both the input and output
of the syntax transformer, so that it identifies every piece of syntax
that was introduced by the transformer (see
@secref["transformer-model"]). The expander attaches this
certificate to parts of the transformer's result, depending on the
shape and properties of the result:

@itemize[

 @item{If the result has a @indexed-scheme['certify-mode] property
          (see @secref["stxprops"]) that is
          @indexed-scheme['opaque], then the certificate is attached
          to the immediate syntax object.}

 @item{If the result has a @scheme['certify-mode] property that is
          @indexed-scheme['transparent], then the certificate is also
          propagated recursively to syntax object that corresponds to
          elements of the syntax object's datum as a list (or, more
          precisely, to the @scheme[car]s of the datum as reached by
          any number of @scheme[cdr]s). This recursive propagation
          uses syntax properties and shapes, as for the immediate
          attachment.}

 @item{If the result has a @scheme['certify-mode] property that is
          @indexed-scheme['transparent-binding], then the certificate
          is attached to similar to @scheme['transparent], but further
          treating the syntax object corresponding to the second list
          element as having a @scheme['transparent] value for the
          @scheme['certify-mode] property if it does not already have
          a @scheme['certify-mode] property value.}

 @item{If the result has no @scheme['certify-mode] property value, but
          its datum is a pair, and if the syntax object corresponding
          to the @scheme[car] of the pair is an identifier bound to
          @scheme[begin], @scheme[module], or
          @scheme[#%plain-module-begin], then the certificate is
          propagated as if the syntax object had the
          @scheme['transparent] property value.}

 @item{If the result has no @scheme['certify-mode] property value,
          but its datum is a pair, and if the syntax object
          corresponding to the @scheme[car] of the pair is an
          identifier bound to @scheme[define-values] or
          @scheme[define-syntaxes], then the certificate is propagated
          as if the syntax object had the @scheme['transparent-binding]
          property value.}

]

To avoid accidental transfer for a @scheme['certify-mode] property
value, the expander always removes any @scheme['certify-mode] property
on a syntax object that is passed to a syntax transformer.

As the expander attaches a new active certificate to a syntax object,
it also removes any @tech{inactive certificates} attached to any
@tech{syntax object} within the one where the certificate is attached,
and it re-attaches the formerly @tech{inactive certificates} as
@tech{active certificates} along with the new one.

As the expander processes a form, it accumulates @tech{active
certificates} that are attached to enclosing forms as part of the
expansion context:

@itemize[

 @item{To check access to an unexported identifier, the expander
   checks each of the identifier's marks and module bindings; if, for
   some mark, the identifier's enclosing expressions include a
   certificate with the mark, the identifier's binding module, and
   with an inspector that controls the module's invocation (as opposed
   to the module's declaration; see again @secref["modprotect"]),
   then the access is allowed. To check access to a protected
   identifier, only the certificate's mark and inspector are used
   (i.e., the module that bound the transformer is irrelevant, as long
   as it was evaluated with a sufficiently powerful inspector). The
   certificate key is not used in checking references.}

 @item{To check access to a locally bound identifier, the expander
   checks the marks of the binding and reference identifiers; for
   every mark that they have in common, if the reference identifier
   has a certificate for the mark from an enclosing expression, the
   binding identifier must have a certificate for the mark from an
   enclosing expression, otherwise the reference is disallowed. (The
   reference identifier can have additional certificates for marks
   that are not attached to the binding identifier.) The binding
   module (if any) and the certificate key are not used for checking a
   local reference.}

 @item{When the expander encounters a @scheme[quote-syntax] form, it
   attaches all accumulated @tech{active certificates} from the
   expressions's context to the quoted syntax objects. A certificate
   for the enclosing module (if any) is also included. The
   certificates are attached as @tech{inactive certificates} to the
   immediate syntax object (i.e., not to any nested syntax
   objects). In addition, any inactive certificates within the quoted
   syntax object are lifted to the immediate syntax object.}

]

Finally, for the result of @scheme[expand] or @scheme[local-expand]
with an empty stop list, certificates are lifted to the outermost
result expression, except to the degree that @scheme['certify-mode]
property values and bindings like @scheme[begin] direct certificates
to sub-expressions.


@defproc[(syntax-recertify [new-stx syntax?]
                           [old-stx syntax?]
                           [inspector inspector?]
                           [key any/c])
         syntax?]{

Copies certain certificates of @scheme[old-stx] to @scheme[new-stx]: a
certificate is copied if its inspector is either @scheme[inspector] or
controlled by @scheme[inspector], or if the certificate's key is
@scheme[key]; otherwise the certificate is not copied.  The result is
a syntax object like @scheme[new-stx], but with the copied
certificates. (The @scheme[new-stx] object itself is not modified.)
Both @tech{active certificates} and @tech{inactive certificates} are
copied.}
