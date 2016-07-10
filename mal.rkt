#lang racket
(require xml xml/path net/url net/uri-codec net/http-client net/base64)
(provide (all-defined-out))

;-----------------------------------------------------------------------------------------
#| URLS |#
;-----------------------------------------------------------------------------------------
(define MAL "http://myanimelist.net/")
(define HOST (string->url MAL))
(define AUTH-STRING "account/verify_credentials.xml")
(define ANIME "anime/")
(define MANGA "manga/")
(define SEARCH "search.xml?q=")
(define ADD "add/")
(define UPDATE "update/")
(define DELETE "delete/")
(define API (combine-url/relative HOST "api/"))

;-----------------------------------------------------------------------------------------
#| XML |#
;-----------------------------------------------------------------------------------------
; XML -> Xexpr
(define xml-values
  (compose1 xml->xexpr (eliminate-whitespace '(entry)) document-element
            read-xml/document))

; These contain the default values from MAL's API guide.
(define anime-values (xml-values (open-input-file "animevalues.xml")))
(define manga-values (xml-values (open-input-file "mangavalues.xml")))

; Xexpr-Element := [List Symbol [Or Empty [Listof Symbol]] Content]
; Content := String | [Listof Xexpr-Element] | '()
; Xexpr Symbol String -> Xexpr
; Update the content of an xexpr element with the new content given.
; Look into doing this with pattern matching.
(define (set-xexpr-content xexpr name content)
  (define content-list (rest (rest xexpr)))
  (define (set-content a-list)
    (cond
      [(empty? a-list) '()]
      [else
       (define elem (first a-list))
       (cond
         [(symbol=? (first elem) name)
          (define new-elem (cons name (cons (second elem) (cons content '()))))
          (cons new-elem (rest a-list))]
         [else (cons (first a-list) (set-content (rest a-list)))])]))
  (cons (first xexpr) (cons (second xexpr) (set-content content-list))))
;-----------------------------------------------------------------------------------------
#| BOILERPLATE |#
;-----------------------------------------------------------------------------------------
; "racket -it mal.rkt yourusername

; If launched from the command-line with the appropriate arguments for a username and
; password, parameterize user and pass with those arguments. Otherwise, parameterize both
; to "default".
(define-values (user pass)
  (let ([arguments (current-command-line-arguments)])
    (if (= (vector-length arguments) 2)
        (values (make-parameter (vector-ref arguments 0))
                (make-parameter (vector-ref arguments 1)))
        (values (make-parameter "default")
                (make-parameter "default")))))

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
  [(compose1 string-trim bytes->string/utf-8
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
  [(apply compose1
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
  (compose1 normalize-mal xml->xexpr (eliminate-whitespace '(anime manga entry))
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
  (mal-action get-pure-port
              API AUTH-STRING))

; String String -> Xexpr
; Returns an Xexpr detailing the search results. Category is a string: either
; ANIME or MANGA.
(define (search category query)
  (mal-action get-pure-port
              API category
              (string-append SEARCH (form-urlencoded-encode query))))

; String String -> String
; Drops the last character of the first string, appends the suffix string, then reattaches
; the last character. Here, the last character is "/".
(define (category+suffix str sfx)
  (define last-char (string-length str))
  (string-append (substring str 0 (sub1 last-char))
                 sfx
                 (substring str (sub1 last-char) last-char)))

; Xexpr -> Bytes/UTF-8
(define xexpr->bytes/utf-8
  (compose1 string->bytes/utf-8 xexpr->string))

; String Xexpr Number -> String?
; Requires a category (either ANIME or MANGA) and XML-Values representation of
; an anime or manga to add, and said anime/manga's ID number.
; Returns a String that mal-action is an inconvenient about parsing. Needs testing.
(define (add category xml-values id)
  (mal-action (λ (url header)
                (post-pure-port url (xexpr->bytes/utf-8 xml-values) header))
              API (category+suffix category "list") ADD
              (string-append (number->string id) ".xml")))
#|
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
