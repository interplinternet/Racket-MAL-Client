<div id="table-of-contents">
<h2>Table of Contents</h2>
<div id="text-table-of-contents">
<ul>
<li><a href="#orgheadline1">1. Use</a></li>
<li><a href="#orgheadline2">2. Authorization</a></li>
<li><a href="#orgheadline8">3. XML Processing</a>
<ul>
<li><a href="#orgheadline5">3.1. mal-&gt;xexpr</a>
<ul>
<li><a href="#orgheadline3">3.1.1. normalize-mal</a></li>
<li><a href="#orgheadline4">3.1.2. remove-html</a></li>
</ul>
</li>
<li><a href="#orgheadline6">3.2. xml-values</a></li>
<li><a href="#orgheadline7">3.3. set-xexpr-content</a></li>
</ul>
</li>
<li><a href="#orgheadline11">4. Actions</a>
<ul>
<li><a href="#orgheadline9">4.1. Search</a></li>
<li><a href="#orgheadline10">4.2. Add/Update/Delete</a></li>
</ul>
</li>
<li><a href="#orgheadline16">5. Boilerplate</a>
<ul>
<li><a href="#orgheadline12">5.1. combine-url*/relative</a></li>
<li><a href="#orgheadline13">5.2. mal-action</a></li>
<li><a href="#orgheadline14">5.3. mal-list-action</a></li>
<li><a href="#orgheadline15">5.4. category+suffix</a></li>
</ul>
</li>
<li><a href="#orgheadline20">6. Examples</a>
<ul>
<li><a href="#orgheadline17">6.1. Searching for "Full Metal Alchemist"</a></li>
<li><a href="#orgheadline18">6.2. Pulling the synopsis of Full Metal Alchemist from that search, using Simple X-expression Path Queries</a></li>
<li><a href="#orgheadline19">6.3. Combining a number of strings with a base URL in one call to create a single new URL</a></li>
</ul>
</li>
<li><a href="#orgheadline21">7. <span class="todo TODO">TODO</span> <code>[2/2]</code></a></li>
</ul>
</div>
</div>

This is a command-line client for the MAL API, supporting searching manga and anime from within a Racket REPL. 

# Use<a id="orgheadline1"></a>

First enter the following at the command-line: `racket -it mal.rkt yourusername yourpassword` or `require` the module at the REPL. If you didn't run the module from the command-line, then the username and password will both be set to "default". To change your username and password, just call `(re-auth! String String)`, where `String` is your username or password. Calling `user` or `pass` without arguments will return their current value (e.g., `(user)` will return your username) and calling them with arguments will parameterize their values to that argument.

# Authorization<a id="orgheadline2"></a>

MAL authorization is done via a header which must be passed with each REST request.
The authorization data passed is a string: `Authorization: Basic [base64encoded string]`
Where `[base64encoded string]` is the result of appending three strings, "Username" ":" "Password"<sup><a id="fnr.1" class="footref" href="#fn.1">1</a></sup>, converting to bytes so we can encode it in base64, then converting back to a string and removing whitespace.

# XML Processing<a id="orgheadline8"></a>

## mal->xexpr<a id="orgheadline5"></a>

The data returned from a request to MAL via the API is some XML data. It's a little ugly to handle by default, since it includes whitespace for formatting and includes PCDATA and stream locations for each element. We use `read-xml/document` to snip off unnecessary data, select the main element of the XML document, and then eliminate whitespace used by MAL for formatting. Then we transform the XML data from the input port stream to a Racket `Xexpr`, which removes PCDATA and stream locations. Finally, we apply our `normalize-mal` function to the data to make it readable.

### normalize-mal<a id="orgheadline3"></a>

Prettifies MAL-Xexprs. There are two special cases here: A regular list of elements, and a list composed entirely of strings (the synopsis). A regular list of elements has `normalize-one` applied to its head, and then recurses on the tail. A list of strings is first flattened into a single string, and then has `normalize-one` applied to it.<sup><a id="fnr.2" class="footref" href="#fn.2">2</a></sup> `normalize-one` compresses whitespace into a single space, removing "\n" and so forth in the process, and then removes two of the common HTML tags.<sup><a id="fnr.3" class="footref" href="#fn.3">3</a></sup> If the expression its handed is a `cons` and not a `string`, it calls `normalize-mal` on it.

### remove-html<a id="orgheadline4"></a>

This one's a bit of a doozy. We want to take a string, `input-str`, and replace all elements in it which correspond to two particular HTML tags. We could just compose the functions manually, but that doesn't scale. Every time we come across a new HTML tag, we have to wrap the function with another `string-replace`! Instead, it would be better if we could pass the function two lists: one containing elements to be replaced, and one containing their replacements. Then we map `string-replace` to the lists and create new functions now only need to be applied to an input string. However, at this time we don't have the input string yet, which must be the first element `string-replace` takes as input. So we can't just curry string-replace with the target strings. Instead, we can use `curryr` which works "backwards" to a normal currying. So we map `(curryr string-replace)` to the two lists, then we apply `compose` to them so that the result of replacing all target elements in a string becomes the input for the next string-replacement. Finally, we apply the composed function to the input string.

## xml-values<a id="orgheadline6"></a>

Reads an XML document from an input port, selects its element, eliminates whitespace, and then transforms it into an xexpr for editing. Used for acting on anime & manga values from MAL's API guide.

## set-xexpr-content<a id="orgheadline7"></a>

Consumes an Xexpr, a Symbol representing an element's name, and some content. It steps through the xexpr looking for an element whose name matches the one given, then returns the entire xexpr with that element's content replaced with the content given.

# Actions<a id="orgheadline11"></a>

## Search<a id="orgheadline9"></a>

Searching works for anime and manga.
`(search category query)` will return an XML document containing the results of your query, where `category` is either the constants ANIME or MANGA.

## Add/Update/Delete<a id="orgheadline10"></a>

Consumes a string (ANIME or MANGA) representing the category, a symbol representing the name of the field in the xml-values to change, and the content to replace it with, and the ID of the anime/manga to work on. Search, update, and delete all work on both anime & manga. Utilizes mal-list-action. Originally tried to use a regular HTTP POST request with data, but MAL is weird. I used HTTP GET and pass data in the URL. Adding returns broken HTML, MAL's <meta &#x2026;> tag is broken it looks like.

# Boilerplate<a id="orgheadline16"></a>

## combine-url\*/relative<a id="orgheadline12"></a>

This is like `combine-url/relative`, but can take multiple strings and create a single URL from them, whereas the original can only take one at a time and you have to manually wrap each call in another in order for it to be the base-url for another string.

## mal-action<a id="orgheadline13"></a>

Since most actions on the MAL API are similarly structured, we can abstract over it with another function.
First use `call/input-url` which will handle the opening and closing of ports automatically, then combine the strings given, ensuring the first string is the main URL as you would normally type it, use your port-handling function such as `get-pure-port` or `post-pure-port`, etc., and pass the function which will handle the output. Since the output is XML, we pass `mal->xexpr`. The last element is a list representing header data, which is only our authorization.

## mal-list-action<a id="orgheadline14"></a>

Layers over `mal-action` with information specific to adding/updating/deleting. Consumes a string representing an action, like ADD/UPDATE/DELETE, and returns a function which takes four arguments to pass to mal-action as well as calling to set-xexpr-content to pass the appropriately updated xml-values.

## category+suffix<a id="orgheadline15"></a>

Takes a base string and separates the last char, then sticks the second string between those two new substrings.

# Examples<a id="orgheadline20"></a>

## Searching for "Full Metal Alchemist"<a id="orgheadline17"></a>

`(search ANIME "Full Metal Alchemist")`
=> 
'(anime
  ()
  (entry
   ()
   (id () "121")
   (title () "Fullmetal Alchemist")
   (english () "Fullmetal Alchemist")
   (synonyms () "Hagane no Renkinjutsushi; FMA; Full Metal Alchemist")
   (episodes () "51")
   (score () "8.34")
   (type () "TV")
   (status () "Finished Airing")
   (start<sub>date</sub> () "2003-10-04")
   (end<sub>date</sub> () "2004-10-02")
   (synopsis
    ()
    "Edward Elric, a young, brilliant alchemist, has lost much in his twelve-year life: when he and his brother Alphonse try to resurrect their dead mother through the forbidden act of human transmutation, Edward loses his brother as well as two of his limbs. With his supreme alchemy skills, Edward binds Alphonse's soul to a large suit of armor.  A year later, Edward, now promoted to the fullmetal alchemist of the state, embarks on a journey with his younger brother to obtain the Philosopher's Stone. The fabled mythical object is rumored to be capable of amplifying an alchemist's abilities by leaps and bounds, thus allowing them to override the fundamental law of alchemy: to gain something, an alchemist must sacrifice something of equal value. Edward hopes to draw into the military's resources to find the fabled stone and restore his and Alphonse's bodies to normal. However, the Elric brothers soon discover that there is more to the legendary stone than meets the eye, as they are led to the epicenter of a far darker battle than they could have ever imagined.  [Written by MAL Rewrite]")
   (image () "![img](//cdn.myanimelist.net/images/anime/10/75815.jpg)")))

## Pulling the synopsis of Full Metal Alchemist from that search, using Simple X-expression Path Queries<a id="orgheadline18"></a>

`(se-path* '(synopsis) (search ANIME "Full Metal Alchemist"))`
=>
"Edward Elric, a young, brilliant alchemist, has lost much in his twelve-year life: when he and his brother Alphonse try to resurrect their dead mother through the forbidden act of human transmutation, Edward loses his brother as well as two of his limbs. With his supreme alchemy skills, Edward binds Alphonse's soul to a large suit of armor.  A year later, Edward, now promoted to the fullmetal alchemist of the state, embarks on a journey with his younger brother to obtain the Philosopher's Stone. The fabled mythical object is rumored to be capable of amplifying an alchemist's abilities by leaps and bounds, thus allowing them to override the fundamental law of alchemy: to gain something, an alchemist must sacrifice something of equal value. Edward hopes to draw into the military's resources to find the fabled stone and restore his and Alphonse's bodies to normal. However, the Elric brothers soon discover that there is more to the legendary stone than meets the eye, as they are led to the epicenter of a far darker battle than they could have ever imagined.  [Written by MAL Rewrite]"

## Combining a number of strings with a base URL in one call to create a single new URL<a id="orgheadline19"></a>

`(combine-url*/relative API ANIME (string-append SEARCH "full metal alchemist"))`
=> 
"<http://myanimelist.net/api/anime/search.xml?q=full+metal+alchemist>"
We have to append SEARCH and the query because "search.xml?q=" is not considered a URL element which can be combined with another.

# TODO <code>[2/2]</code><a id="orgheadline21"></a>

-   [X] Allow conditional loading of command-line arguments. If you try to reload the module while already in Emacs, you receive an error and it doesn't load at all because there are no command line arguments. If there are no command line arguments, just parameterize the user and pass to "default" and "default" and let the user insert their own manually via (user "myusername") and (pass "mypassword").
-   [X] Allow for adding/updating/deleting anime & manga values from within the module.

<div id="footnotes">
<h2 class="footnotes">Footnotes: </h2>
<div id="text-footnotes">

<div class="footdef"><sup><a id="fn.1" class="footnum" href="#fnr.1">1</a></sup> <div class="footpara">Unfortunately, MAL does not encrypt your data and the API is HTTP only, whoops!</div></div>

<div class="footdef"><sup><a id="fn.2" class="footnum" href="#fnr.2">2</a></sup> <div class="footpara">I considered using a foldr expression here, due to the recursive nature of the processing, but having a special case of a list of strings and regular single string elements made it troublesome.</div></div>

<div class="footdef"><sup><a id="fn.3" class="footnum" href="#fnr.3">3</a></sup> <div class="footpara">If anyone knows of a convenient database of all HTML tags I could shove in here, that would be great.</div></div>


</div>
</div>
