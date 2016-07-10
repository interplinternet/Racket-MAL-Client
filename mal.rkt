#lang racket
(require xml xml/path net/url net/uri-codec net/http-client net/base64)
(provide (all-defined-out))
(define MAL "http://myanimelist.net/")
(define HOST (string->url MAL))
(define AUTH-STRING "account/verify_credentials.xml")
(define ANIME "anime/")
(define MANGA "manga/")
(define SEARCH "search.xml?q=")
(define API (combine-url/relative HOST "api/"))

; "racket -it mal.rkt yourusername yourpass -i"
;(define arguments (current-command-line-arguments))

(define user (make-parameter (vector-ref arguments 0)))
(define pass (make-parameter (vector-ref arguments 1)))

; URL [Listof String] -> URL
; combines a series of strings into one URL path.
; ex (combine-url*/relative API ANIME SEARCH "full metal alchemist")
(define (combine-url*/relative base-url . strs)
  (define (combiner url los)
    (cond
      [(empty? los) url]
      [else (combiner (combine-url/relative url (first los)) (rest los))]))
  (combiner base-url strs))
;-----------------------------------------------------------------------------------------
#| AUTHORIZATION |#
;-----------------------------------------------------------------------------------------
; -> String
(define (auth-header)
  (string-append "Authorization: Basic "
                 (string->encoded (string-append (user) ":" (pass)))))

; String -> String
; Converts a string to bytes, encodes it in base64, then turns it back into a string and
; trims whitespace at the end. Necessary for authorization, MAL excepts your information
; in base64.
(define (string->encoded str)
  [(compose string-trim bytes->string/utf-8
            base64-encode string->bytes/utf-8)
   str])

(define current-auth (make-parameter (auth-header)))
;-----------------------------------------------------------------------------------------
#| XML PROCESSING |#
;-----------------------------------------------------------------------------------------
; MAL-Xexpr := '()
;            | Symbol
;            | String
;            | [Listof MAL-Xexpr]

; MAL-Xexpr -> Xexpr
; Prettifies MAL XML by appending strings together and removing html tags.
(define (normalize-mal xexpr)
  ; Xexpr -> Xexpr
  (define (normalize-one xpr)
    (cond
      [(string? xpr) (remove-html (string-normalize-spaces xpr))]
      [(cons? xpr) (normalize-mal xpr)]
      [else xpr]))
  ; - IN -
  (match xexpr
    ['() '()]
    [(list (? string? str) ...)
     (list (normalize-one (string-append* str)))]
    [(cons head tail)
     (cons (normalize-one head) (normalize-mal tail))]
    [_ xexpr]))

; String -> String
; Repeatedly apply a string-replace function to one string. String-replace can
; only take one replacement per application to a string. Replace the call to
; string-replace with an anonymous functions so we can reorder the arguments, so
; that the string to be applied to can be the last argument taken. Then we can
; take two lists, one being a list of target strings and one of replacements,
; and map the anonymous function to them, leading to a list of curried
; functions. Or just use curryr, since that does the same reordering for me!
; Since each curried function is reordered, they can be applied
; directly to a string. Now we apply compose to the list of curried functions,
; which chains them together such that the output to each is the input to the
; next. Finally, we apply that final function to the input string.
(define (remove-html input-str)
  [(apply compose
          (map
           (curryr string-replace)
           '("&#039;" "<br />") '("'" "")))
   input-str])

; Document -> Xexpr
; Takes an XML document and prettifies it. Since the input comes from a port,
; the library includes PCDATA content and the location in the stream of each
; element. It also includeds a lot of needless whitespace, e.g., "\n    ", as
; formatting placeholders. Then it converts the xml expression into a normal
; racket Xexpr for manipulation.
(define mal->xexpr
  (compose normalize-mal xml->xexpr (eliminate-whitespace '(anime entry))
           document-element read-xml/document))
;-----------------------------------------------------------------------------------------
#| ACTIONS |#
;-----------------------------------------------------------------------------------------
(define (mal-action port-func . str)
  (call/input-url (apply combine-url*/relative str)
                  port-func
                  mal->xexpr
                  (list (current-auth))))
; -> XML
; Calls the current parameter for the users authorization info and sends it to MAL,
; returning a xexpr containing the users authorization info.
(define (authorize) 
  (call/input-url (combine-url/relative API AUTH-STRING)
                  get-pure-port
                  mal->xexpr
                  (list (current-auth))))

; String String -> Xexpr
; Returns an Xexpr detailing the search results. Category is a string: either
; ANIME or MANGA.
(define (search category query)
  ; uses parameters
  (mal-action get-pure-port
              API category
              (string-append SEARCH (form-urlencoded-encode query)))
  #| (call/input-url
  (combine-url*/relative API category
  (string-append SEARCH (form-urlencoded-encode query)))
  get-pure-port
  mal->xexpr
  (list (current-auth)))|#)

; String Number -> Xexpr
; this is broken. How am I supposed to grab the appropriate XML values for an anime if I
; only have the ID? There's no defined way to just view the "Anime Values" of a series
; with only its ID. Searching is done by name, not by ID. MAL API sucks. Check
; MALappinfo.php for more information on the old API.
#| ; category must be (anime|manga)list
(define (add category id)
  (call/input-url
   (combine-url*/relative API category "add/"
                          (string-append (number->string id) ".xml"))
   (λ (url headr) (post-pure-port url #"appropriate bytestring" headr))
   mal->xexpr
   (list (current-auth))))

(define (delete category id)
  ...)

(define (update category id)
  ...)|#
;-----------------------------------------------------------------------------------------
#| EXAMPLES |#
;-----------------------------------------------------------------------------------------
#|  (define ex-auth (authorize))
(define ex-search (search ANIME "full metal alchemist"))
(define normal-ex (normalize-mal ex-search))
(define ex-synopsis (se-path* '(synopsis) ex-search))|#
