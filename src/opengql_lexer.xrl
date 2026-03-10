Definitions.
WS = [\000-\s]+
ID = [A-Za-z_][A-Za-z0-9_]*
INT = [-+]?[0-9]+
STR = "[^"]*"

Rules.
{WS} : skip_token.
[<][-] : {token, {left_arrow, TokenLine}}.
[-][>] : {token, {right_arrow, TokenLine}}.
[<][=] : {token, {comp_op, TokenLine, lte}}.
[>][=] : {token, {comp_op, TokenLine, gte}}.
[!][=] : {token, {comp_op, TokenLine, neq}}.
[<][>] : {token, {comp_op, TokenLine, neq}}.
[=] : {token, {comp_op, TokenLine, eq}}.
[<] : {token, {comp_op, TokenLine, lt}}.
[>] : {token, {comp_op, TokenLine, gt}}.
[-] : {token, {dash, TokenLine}}.
[(] : {token, {lparen, TokenLine}}.
[)] : {token, {rparen, TokenLine}}.
[{] : {token, {lbrace, TokenLine}}.
[}] : {token, {rbrace, TokenLine}}.
[\[] : {token, {lbrack, TokenLine}}.
[\]] : {token, {rbrack, TokenLine}}.
[:] : {token, {colon, TokenLine}}.
[,] : {token, {comma, TokenLine}}.
[.] : {token, {dot, TokenLine}}.
[*] : {token, {star, TokenLine}}.
[|] : {token, {pipe, TokenLine}}.
[;] : {token, {semicolon, TokenLine}}.
{INT} : {token, {integer, TokenLine, list_to_integer(TokenChars)}}.
{STR} : {token, {string, TokenLine, strip_quotes(TokenChars)}}.
{ID} : {token, classify_identifier(TokenChars, TokenLine)}.

Erlang code.

strip_quotes(TokenChars) ->
    InnerLen = length(TokenChars) - 2,
    unicode:characters_to_binary(lists:sublist(TokenChars, 2, InnerLen)).

to_binary(TokenChars) ->
    unicode:characters_to_binary(TokenChars).

classify_identifier(TokenChars, TokenLine) ->
    case string:uppercase(TokenChars) of
        "MATCH" -> {match, TokenLine};
        "CREATE" -> {create, TokenLine};
        "SET" -> {set, TokenLine};
        "DELETE" -> {delete, TokenLine};
        "DETACH" -> {detach, TokenLine};
        "RETURN" -> {return, TokenLine};
        "WHERE" -> {where, TokenLine};
        "FILTER" -> {filter, TokenLine};
        "ORDER" -> {order, TokenLine};
        "BY" -> {by, TokenLine};
        "LIMIT" -> {limit, TokenLine};
        "OFFSET" -> {offset, TokenLine};
        "SKIP" -> {skip, TokenLine};
        "FINISH" -> {finish, TokenLine};
        "AND" -> {logical_op, TokenLine, 'and'};
        "OR" -> {logical_op, TokenLine, 'or'};
        "XOR" -> {logical_op, TokenLine, 'xor'};
        "NOT" -> {not_kw, TokenLine};
        "IS" -> {is_kw, TokenLine};
        "IN" -> {in_kw, TokenLine};
        "BETWEEN" -> {between, TokenLine};
        "CONTAINS" -> {contains, TokenLine};
        "STARTS" -> {starts, TokenLine};
        "ENDS" -> {ends, TokenLine};
        "WITH" -> {with_kw, TokenLine};
        "ASC" -> {direction, TokenLine, asc};
        "DESC" -> {direction, TokenLine, desc};
        "TRUE" -> {boolean, TokenLine, true};
        "FALSE" -> {boolean, TokenLine, false};
        "NULL" -> {null, TokenLine, nil};
        _ -> {identifier, TokenLine, to_binary(TokenChars)}
    end.