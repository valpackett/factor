! Copyright (C) 2006 Chris Double, 2008 Peter Burns, 2009 Philipp Winkler

USING: accessors ascii assocs combinators formatting hashtables
io io.encodings.utf16.private io.encodings.utf8 io.files
io.streams.string kernel kernel.private math math.order
math.parser mirrors namespaces sbufs sequences sequences.private
strings summary tr words ;

IN: json

SINGLETON: json-null

ERROR: json-error ;

ERROR: json-fp-special-error value ;

M: json-fp-special-error summary
    drop "JSON serialization: illegal float:" ;

: if-json-null ( x if-null else -- )
    [ dup json-null? ]
    [ [ drop ] prepose ]
    [ ] tri* if ; inline

: when-json-null ( x if-null -- ) [ ] if-json-null ; inline

: unless-json-null ( x else -- ) [ ] swap if-json-null ; inline

<PRIVATE

ERROR: not-a-json-number string ;

SYMBOL: json-depth

: json-number ( char stream -- num char )
    [ 1string ] [ "\s\t\r\n,:}]" swap stream-read-until ] bi*
    [
        append {
            { "Infinity" [ 1/0. ] }
            { "-Infinity" [ -1/0. ] }
            { "NaN" [ 0/0. ] }
            [ [ string>number ] [ not-a-json-number ] ?unless ]
        } case
    ] dip ;

: json-expect ( token stream -- )
    [ dup length ] [ stream-read ] bi* = [ json-error ] unless ; inline

DEFER: (read-json-string)

: decode-utf16-surrogate-pair ( hex1 hex2 -- char )
    [ 0x3ff bitand ] bi@ [ 10 shift ] dip bitor 0x10000 + ;

: stream-read-4hex ( stream -- hex ) 4 swap stream-read hex> ;

: first-surrogate? ( hex -- ? ) 0xd800 0xdbff between? ;

: read-second-surrogate ( stream -- hex )
    "\\u" over json-expect stream-read-4hex ;

: read-json-escape-unicode ( stream -- char )
    [ stream-read-4hex ] keep over first-surrogate? [
        read-second-surrogate decode-utf16-surrogate-pair
    ] [ drop ] if ;

: (read-json-escape) ( stream accum -- accum )
    { sbuf } declare
    over stream-read1 {
        { CHAR: \" [ CHAR: \" ] }
        { CHAR: \\ [ CHAR: \\ ] }
        { CHAR: / [ CHAR: / ] }
        { CHAR: b [ CHAR: \b ] }
        { CHAR: f [ CHAR: \f ] }
        { CHAR: n [ CHAR: \n ] }
        { CHAR: r [ CHAR: \r ] }
        { CHAR: t [ CHAR: \t ] }
        { CHAR: u [ over read-json-escape-unicode ] }
        [ ]
    } case [ suffix! (read-json-string) ] [ json-error ] if* ;

: (read-json-string) ( stream accum -- accum )
    { sbuf } declare
    "\\\"" pick stream-read-until [ append! ] dip
    CHAR: \" = [ nip ] [ (read-json-escape) ] if ;

: read-json-string ( stream -- str )
    "\\\"" over stream-read-until CHAR: \" =
    [ nip ] [ >sbuf (read-json-escape) "" like ] if ;

: second-last-unsafe ( seq -- second-last )
    [ length 2 - ] [ nth-unsafe ] bi ; inline

: pop-unsafe ( seq -- elt )
    index-of-last [ nth-unsafe ] [ shorten ] 2bi ; inline

: check-length ( seq n -- seq )
    [ dup length ] [ >= ] bi* [ json-error ] unless ; inline

: v-over-push ( accum -- accum )
    2 check-length dup [ pop-unsafe ] [ last-unsafe ] bi push ;

: v-pick-push ( accum -- accum )
    3 check-length dup [ pop-unsafe ] [ second-last-unsafe ] bi push ;

: v-close ( accum -- accum )
    dup last V{ } = not [ v-over-push ] when ;

: json-open-array ( accum -- accum )
    V{ } clone suffix! ;

: json-open-hash ( accum -- accum )
    V{ } clone suffix! V{ } clone suffix! ;

: json-close-array ( accum -- accum )
    v-close dup pop { } like suffix! ;

: json-close-hash ( accum -- accum )
    v-close dup dup [ pop ] bi@ swap H{ } zip-as suffix! ;

: scan ( stream accum char -- stream accum )
    ! 2dup 1string swap . . ! Great for debug...
    {
        { CHAR: \" [ over read-json-string suffix! ] }
        { CHAR: [  [ 1 json-depth +@ json-open-array ] }
        { CHAR: ,  [ v-over-push ] }
        { CHAR: ]  [ -1 json-depth +@ json-close-array ] }
        { CHAR: {  [ json-open-hash ] }
        { CHAR: :  [ v-pick-push ] }
        { CHAR: }  [ json-close-hash ] }
        { CHAR: \s [ ] }
        { CHAR: \t [ ] }
        { CHAR: \r [ ] }
        { CHAR: \n [ ] }
        { CHAR: t  [ "rue" pick json-expect t suffix! ] }
        { CHAR: f  [ "alse" pick json-expect f suffix! ] }
        { CHAR: n  [ "ull" pick json-expect json-null suffix! ] }
        [ pick json-number [ suffix! ] dip [ scan ] when*  ]
    } case ;

: json-read-input ( stream -- objects )
    0 json-depth [
        V{ } clone over '[ _ stream-read1 ] [ scan ] while* nip
        json-depth get zero? [ json-error ] unless
    ] with-variable ;

: get-json ( objects  --  obj )
    dup length 1 = [ first ] [ json-error ] if ;

PRIVATE>

: read-json ( -- objects )
    input-stream get json-read-input ;

GENERIC: json> ( string -- object )

M: string json>
    [ read-json get-json ] with-string-reader ;

: path>json ( path -- json )
    utf8 [ read-json get-json ] with-file-reader ;

: path>jsons ( path -- jsons )
    utf8 [ read-json ] with-file-reader ;

SYMBOL: json-allow-fp-special?
f json-allow-fp-special? set-global

SYMBOL: json-friendly-keys?
t json-friendly-keys? set-global

SYMBOL: json-coerce-keys?
t json-coerce-keys? set-global

SYMBOL: json-escape-slashes?
f json-escape-slashes? set-global

SYMBOL: json-escape-unicode?
f json-escape-unicode? set-global

! Writes the object out to a stream in JSON format
GENERIC#: stream-json-print 1 ( obj stream -- )

: json-print ( obj -- )
    output-stream get stream-json-print ;

: >json ( obj -- string )
    ! Returns a string representing the factor object in JSON format
    [ json-print ] with-string-writer ;

M: f stream-json-print
    [ drop "false" ] [ stream-write ] bi* ;

M: t stream-json-print
    [ drop "true" ] [ stream-write ] bi* ;

M: json-null stream-json-print
    [ drop "null" ] [ stream-write ] bi* ;

<PRIVATE

: json-print-generic-escape-surrogate-pair ( stream char -- stream )
    0x10000 - [ encode-first ] [ encode-second ] bi
    "\\u%02x%02x\\u%02x%02x" sprintf over stream-write ;

: json-print-generic-escape-bmp ( stream char -- stream )
    "\\u%04x" sprintf over stream-write ;

: json-print-generic-escape ( stream char -- stream )
    dup 0xffff > [
        json-print-generic-escape-surrogate-pair
    ] [
        json-print-generic-escape-bmp
    ] if ;

PRIVATE>

M: string stream-json-print
    CHAR: \" over stream-write1 swap [
        {
            { CHAR: \"  [ "\\\"" over stream-write ] }
            { CHAR: \\ [ "\\\\" over stream-write ] }
            { CHAR: /  [
                json-escape-slashes? get
                [ "\\/" over stream-write ]
                [ CHAR: / over stream-write1 ] if
            ] }
            { CHAR: \b [ "\\b" over stream-write ] }
            { CHAR: \f [ "\\f" over stream-write ] }
            { CHAR: \n [ "\\n" over stream-write ] }
            { CHAR: \r [ "\\r" over stream-write ] }
            { CHAR: \t [ "\\t" over stream-write ] }
            { 0x2028   [ "\\u2028" over stream-write ] }
            { 0x2029   [ "\\u2029" over stream-write ] }
            [
                {
                    { [ dup printable? ] [ f ] }
                    { [ dup control? ] [ t ] }
                    [ json-escape-unicode? get ]
                } cond [
                    json-print-generic-escape
                ] [
                    over stream-write1
                ] if
            ]
        } case
    ] each CHAR: \" swap stream-write1 ;

M: integer stream-json-print
    [ number>string ] [ stream-write ] bi* ;

: float>json ( float -- string )
    dup fp-special? [
        json-allow-fp-special? get [ json-fp-special-error ] unless
        {
            { [ dup fp-nan? ] [ drop "NaN" ] }
            { [ dup 1/0. = ] [ drop "Infinity" ] }
            { [ dup -1/0. = ] [ drop "-Infinity" ] }
        } cond
    ] [
        number>string
    ] if ;

M: float stream-json-print
    [ float>json ] [ stream-write ] bi* ;

M: real stream-json-print
    [ >float number>string ] [ stream-write ] bi* ;

M: sequence stream-json-print
    CHAR: [ over stream-write1 swap
    over '[ CHAR: , _ stream-write1 ]
    pick '[ _ stream-json-print ] interleave
    CHAR: ] swap stream-write1 ;

<PRIVATE

TR: json-friendly "-" "_" ;

GENERIC: json-coerce ( obj -- str )
M: f json-coerce drop "false" ;
M: t json-coerce drop "true" ;
M: json-null json-coerce drop "null" ;
M: string json-coerce ;
M: integer json-coerce number>string ;
M: float json-coerce float>json ;
M: real json-coerce >float number>string ;

:: json-print-assoc ( obj stream -- )
    CHAR: { stream stream-write1 obj >alist
    [ CHAR: , stream stream-write1 ]
    json-friendly-keys? get
    json-coerce-keys? get '[
        first2 [
            dup string?
            [ _ [ json-friendly ] when ]
            [ _ [ json-coerce ] when ] if
            stream stream-json-print
        ] [
            CHAR: : stream stream-write1
            stream stream-json-print
        ] bi*
    ] interleave
    CHAR: } stream stream-write1 ;

PRIVATE>

M: tuple stream-json-print
    [ <mirror> ] dip json-print-assoc ;

M: hashtable stream-json-print json-print-assoc ;

M: word stream-json-print
    [ name>> ] dip stream-json-print ;
