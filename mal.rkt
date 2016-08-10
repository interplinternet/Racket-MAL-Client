#lang racket
(require xml xml/path net/url net/uri-codec net/http-client net/base64 html)
(provide (all-defined-out))

;;---------------------------------------------------------------------------------------------------
#| URLS |#

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

#| HTML |#
(define REPLACE-ME '("&#039;" "<br />"))
(define REPLACE-WITH '("'" ""))


#| XML |#
(define XML-HEADER "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")

;;---------------------------------------------------------------------------------------------------
#| BOILERPLATE |#

; "racket -it mal.rkt yourusername yourpassword"

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
  (foldl (λ (los url) (combine-url/relative url los)) base-url strs)
  #| (define (combiner url los)
  (cond
  [(empty? los) url]
  [else (combiner (combine-url/relative url (first los)) (rest los))]))
  (combiner base-url strs)|#)

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
  (compose1 string->bytes/utf-8 (curry string-append XML-HEADER) xexpr->string))

; [Input-Port -> X] [X -> Y] [Listof String] -> MAL-Xexpr
(define (mal-action port-func handler . str)
  (call/input-url (apply combine-url*/relative str)
                  port-func
                  handler
                  (list (current-auth))))

; String -> [String Symbol Content Number -> String?]
; Consumes a string representing an action: ADD, UPDATE, DELETE. Returns a function
; consuming a string representing the category to act on, the field name (e.g., status,
; episodes, comments, etc.) and its new value ("1", "tag1"), and the id of the
; anime/manga.
(define ((mal-list-action action) category field-name field-content id)
  (define xml-values
    (set-xexpr-content (match category ["anime/" anime-values] ["manga/" manga-values])
                       field-name field-content))
  ; - IN -
  (mal-action get-pure-port port->string
              API (category+suffix category "list") action
              (string-append (number->string id) ".xml?data="
                             XML-HEADER
                             (xexpr->string xml-values))))
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

; String String -> String
; re-parameterizes user & pass to the input, then re-parameterizes the current-auth with
; that information. Finally, returns a string listing the user & pass parameters as
; confirmation.
(define (re-auth! username password)
  (begin (user username) (pass password) (current-auth (auth-header))
         (~a (user) " : " (pass))))

; -> XML
; Calls the current parameter for the users authorization info and sends it to MAL,
; returning a xexpr containing the users authorization info. Not normally used, but useful
; for debugging or determining user information.
(define (authorize)
  (mal-action get-pure-port mal->xexpr
              API AUTH-STRING))
;-----------------------------------------------------------------------------------------
#| XML PROCESSING |#
;-----------------------------------------------------------------------------------------
; XML -> Xexpr
(define xml-values
  (compose1 xml->xexpr (eliminate-whitespace '(entry)) document-element
            read-xml/document))

; These contain the default values from MAL's API guide.
(define anime-values (xml-values (open-input-file "animevalues.xml")))
(define manga-values (xml-values (open-input-file "mangavalues.xml")))

; Xexpr-Element := [List Symbol [Or Empty [Listof Symbol]] Content]
; Content := String
;          | [Listof Xexpr-Element]
;          | '()
; Xexpr Symbol String -> Xexpr
; Update the content of an xexpr element with the new content given.
(define (set-xexpr-content xexpr name content)
  ; Xexpr -> Xexpr
  (define/match (match-single elem)
    [((list sym attr cnt ...))
     #:when (symbol=? sym name)
     (list name attr content)]
    [((list sym attr cnt ...))
     (list* sym attr (map match-single cnt))]
    [(_) elem])
  ; - IN -
  (match-single xexpr))

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
           REPLACE-ME REPLACE-WITH))
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
; String String -> Xexpr
; Returns an Xexpr detailing the search results. Category is a string: either
; ANIME or MANGA.
(define (search category query)
  (mal-action get-pure-port mal->xexpr
              API category
              (string-append SEARCH (form-urlencoded-encode query))))


; String Xexpr Number -> String
; This works, but returns MAL's broken-ass HTML.
(define add (mal-list-action ADD))

; String Xexpr Number -> String
(define update (mal-list-action UPDATE))

; String Xexpr Number -> String
(define delete (mal-list-action DELETE))
