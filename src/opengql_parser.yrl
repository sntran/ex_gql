Nonterminals
statement
opt_semicolon
clauses
clause
ident_like
match_clause
create_clause
paths
path_more
path
path_tail
node
opt_var
opt_labels
labels_tail
opt_props
prop_entries
prop_tail
prop_entry
edge
edge_inner
opt_edge_var
opt_edge_types
edge_types_tail
set_clause
assignments
assignments_tail
assignment
delete_clause
delete_vars
delete_vars_tail
return_clause
return_items
return_tail
return_item
where_clause
filter_clause
where_expression
where_tail
expr_item
group
condition
property_ref
opt_not
bool_state
list_literal
list_values
list_tail
order_by_clause
order_items
order_tail
order_item
opt_direction
limit_clause
offset_clause
skip_clause
finish_clause
value.

Terminals
match
create
set
delete
detach
return
where
filter
order
by
limit
offset
skip
finish
logical_op
not_kw
is_kw
in_kw
between
contains
starts
ends
with_kw
direction
comp_op
left_arrow
right_arrow
dash
lparen
rparen
lbrace
rbrace
lbrack
rbrack
colon
comma
dot
star
pipe
semicolon
identifier
string
integer
boolean
null.

Rootsymbol statement.

statement -> clauses opt_semicolon : '$1'.

opt_semicolon -> semicolon : ok.
opt_semicolon -> '$empty' : ok.

clauses -> clause clauses : ['$1' | '$2'].
clauses -> clause : ['$1'].

clause -> match_clause : '$1'.
clause -> create_clause : '$1'.
clause -> set_clause : '$1'.
clause -> delete_clause : '$1'.
clause -> return_clause : '$1'.
clause -> where_clause : '$1'.
clause -> filter_clause : '$1'.
clause -> order_by_clause : '$1'.
clause -> limit_clause : '$1'.
clause -> offset_clause : '$1'.
clause -> skip_clause : '$1'.
clause -> finish_clause : '$1'.

match_clause -> match paths : {match, '$2'}.
create_clause -> create paths : {create, '$2'}.

paths -> path path_more : ['$1' | '$2'].
path_more -> comma path path_more : ['$2' | '$3'].
path_more -> '$empty' : [].

path -> node path_tail : {path, ['$1' | '$2']}.
path_tail -> edge node path_tail : ['$1', '$2' | '$3'].
path_tail -> '$empty' : [].

node -> lparen opt_var opt_labels opt_props rparen : {node, build_node_attrs('$2', '$3', '$4')}.

opt_var -> ident_like : '$1'.
opt_var -> '$empty' : none.

opt_labels -> colon ident_like labels_tail : ['$2' | '$3'].
opt_labels -> '$empty' : [].

labels_tail -> colon ident_like labels_tail : ['$2' | '$3'].
labels_tail -> '$empty' : [].

opt_props -> lbrace prop_entries rbrace : [props | '$2'].
opt_props -> '$empty' : none.

prop_entries -> prop_entry prop_tail : '$1' ++ '$2'.
prop_entries -> '$empty' : [].

prop_tail -> comma prop_entry prop_tail : '$2' ++ '$3'.
prop_tail -> '$empty' : [].

prop_entry -> ident_like colon value : ['$1', '$3'].

edge -> dash lbrack edge_inner rbrack right_arrow : {edge_right, '$3'}.
edge -> left_arrow lbrack edge_inner rbrack dash : {edge_left, '$3'}.
edge -> dash lbrack edge_inner rbrack dash : {edge_undirected, '$3'}.

edge_inner -> opt_edge_var opt_edge_types opt_props : build_edge_attrs('$1', '$2', '$3').

opt_edge_var -> ident_like : '$1'.
opt_edge_var -> '$empty' : none.

opt_edge_types -> colon ident_like edge_types_tail : ['$2' | '$3'].
opt_edge_types -> '$empty' : [].

edge_types_tail -> pipe ident_like edge_types_tail : ['$2' | '$3'].
edge_types_tail -> '$empty' : [].

set_clause -> set assignments : {set, '$2'}.
assignments -> assignment assignments_tail : ['$1' | '$2'].
assignments_tail -> comma assignment assignments_tail : ['$2' | '$3'].
assignments_tail -> '$empty' : [].
assignment -> ident_like dot ident_like comp_op value : build_assignment('$1', '$3', '$4', '$5').

delete_clause -> detach delete delete_vars : {detach_delete, [{vars, '$3'}]}.
delete_clause -> delete delete_vars : {delete, [{vars, '$2'}]}.

delete_vars -> ident_like delete_vars_tail : ['$1' | '$2'].
delete_vars_tail -> comma ident_like delete_vars_tail : ['$2' | '$3'].
delete_vars_tail -> '$empty' : [].

return_clause -> return return_items : {return, '$2'}.
return_items -> return_item return_tail : ['$1' | '$2'].
return_tail -> comma return_item return_tail : ['$2' | '$3'].
return_tail -> '$empty' : [].
return_item -> ident_like : '$1'.
return_item -> star : <<"*">>.

where_clause -> where where_expression : {where, '$2'}.
filter_clause -> filter where_expression : {filter, '$2'}.

where_expression -> expr_item where_tail : ['$1' | '$2'].
where_tail -> logical_op expr_item where_tail : [{logical, [token_value('$1')]}, '$2' | '$3'].
where_tail -> '$empty' : [].

expr_item -> not_kw expr_item : {unary, ['$2']}.
expr_item -> group : '$1'.
expr_item -> condition : '$1'.

group -> lparen where_expression rparen : {group, '$2'}.

condition -> property_ref comp_op value : {condition_cmp, ['$1', token_value('$2'), '$3']}.
condition -> property_ref is_kw opt_not null : build_null_condition('$1', '$3').
condition -> property_ref is_kw opt_not bool_state : build_bool_condition('$1', '$3', '$4').
condition -> property_ref opt_not in_kw list_literal : build_in_condition('$1', '$2', '$4').
condition -> property_ref opt_not between value logical_op value : build_between_condition('$1', '$2', '$4', '$5', '$6').
condition -> property_ref contains string : {condition_text, ['$1', contains, {string, token_value('$3')}]}.
condition -> property_ref starts with_kw string : {condition_text, ['$1', starts_with, {string, token_value('$4')}]}.
condition -> property_ref ends with_kw string : {condition_text, ['$1', ends_with, {string, token_value('$4')}]}.

property_ref -> ident_like dot ident_like : {property, ['$1', '$3']}.

opt_not -> not_kw : true.
opt_not -> '$empty' : none.

bool_state -> boolean : token_value('$1').

list_literal -> lbrack list_values rbrack : {list, '$2'}.
list_values -> value list_tail : ['$1' | '$2'].
list_values -> '$empty' : [].
list_tail -> comma value list_tail : ['$2' | '$3'].
list_tail -> '$empty' : [].

order_by_clause -> order by order_items : {order_by, '$3'}.
order_items -> order_item order_tail : ['$1' | '$2'].
order_tail -> comma order_item order_tail : ['$2' | '$3'].
order_tail -> '$empty' : [].
order_item -> property_ref opt_direction : build_order_item('$1', '$2').

opt_direction -> direction : token_value('$1').
opt_direction -> '$empty' : none.

limit_clause -> limit integer : {limit, [token_value('$2')]}.
offset_clause -> offset integer : {offset, [token_value('$2')]}.
skip_clause -> skip integer : {skip, [token_value('$2')]}.
finish_clause -> finish : {finish, [true]}.

value -> string : {string, token_value('$1')}.
value -> integer : {integer, token_value('$1')}.
value -> boolean : {boolean, token_value('$1')}.
value -> null : {null, nil}.

ident_like -> identifier : token_value('$1').
ident_like -> match : ident_token(match).
ident_like -> create : ident_token(create).
ident_like -> set : ident_token(set).
ident_like -> delete : ident_token(delete).
ident_like -> detach : ident_token(detach).
ident_like -> return : ident_token(return).
ident_like -> where : ident_token(where).
ident_like -> filter : ident_token(filter).
ident_like -> order : ident_token(order).
ident_like -> by : ident_token(by).
ident_like -> limit : ident_token(limit).
ident_like -> offset : ident_token(offset).
ident_like -> skip : ident_token(skip).
ident_like -> finish : ident_token(finish).
ident_like -> logical_op : atom_text(token_value('$1')).
ident_like -> not_kw : ident_token('not').
ident_like -> is_kw : ident_token('is').
ident_like -> in_kw : ident_token('in').
ident_like -> between : ident_token(between).
ident_like -> contains : ident_token(contains).
ident_like -> starts : ident_token(starts).
ident_like -> ends : ident_token(ends).
ident_like -> with_kw : ident_token(with).
ident_like -> direction : atom_text(token_value('$1')).
ident_like -> boolean : boolean_to_binary(token_value('$1')).
ident_like -> null : ident_token(null).

Erlang code.

token_value({_, _, Value}) -> Value;
token_value({_, _}) -> undefined.

build_node_attrs(Var, Labels, Props) ->
    maybe_var(Var) ++ maybe_labels(Labels) ++ maybe_props(Props).

build_edge_attrs(Var, Types, Props) ->
    maybe_var(Var) ++ maybe_types(Types) ++ maybe_props(Props).

maybe_var(none) -> [];
maybe_var(Var) -> [{var, [Var]}].

maybe_labels([]) -> [];
maybe_labels(Labels) -> [{labels, Labels}].

maybe_types([]) -> [];
maybe_types(Types) -> [{types, Types}].

maybe_props(none) -> [];
maybe_props(Props) -> [{props, Props}].

build_assignment(VarName, PropName, OpTok, Value) ->
    case token_value(OpTok) of
        eq -> {assignment, [VarName, PropName, Value]};
        _ -> erlang:error({invalid_assignment_operator, token_value(OpTok)})
    end.

build_null_condition(Property, none) -> {condition_null, [Property]};
build_null_condition(Property, true) -> {condition_null, [Property, true]}.

build_bool_condition(Property, none, State) -> {condition_bool, [Property, State]};
build_bool_condition(Property, true, State) -> {condition_bool, [Property, true, State]}.

build_in_condition(Property, none, List) -> {condition_in, [Property, List]};
build_in_condition(Property, true, List) -> {condition_in, [Property, true, List]}.

build_between_condition(Property, NotFlag, Low, LogicalOp, High) ->
    case token_value(LogicalOp) of
        'and' when NotFlag =:= none -> {condition_between, [Property, Low, High]};
        'and' when NotFlag =:= true -> {condition_between, [Property, true, Low, High]};
        _ -> erlang:error(invalid_between_separator)
    end.

build_order_item(Property, none) -> {order_item, [Property]};
build_order_item(Property, Direction) -> {order_item, [Property, Direction]}.

ident_token(Atom) -> erlang:atom_to_binary(Atom, utf8).

boolean_to_binary(true) -> <<"true">>;
boolean_to_binary(false) -> <<"false">>.

atom_text(Atom) -> erlang:atom_to_binary(Atom, utf8).