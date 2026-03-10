defmodule OpenGQL.Parser.Predicate do
  @moduledoc false

  import NimbleParsec

  whitespace =
    ascii_string([?\s, ?\n, ?\r, ?\t], min: 1)
    |> label("whitespace")

  optional_ws =
    ascii_string([?\s, ?\n, ?\r, ?\t], min: 0)
    |> ignore()

  identifier =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})
    |> label("identifier")

  string_literal =
    ignore(ascii_char([?"]))
    |> repeat(
      lookahead_not(ascii_char([?"]))
      |> utf8_char([])
    )
    |> reduce({List, :to_string, []})
    |> ignore(ascii_char([?"]))
    |> unwrap_and_tag(:string)

  integer_value =
    optional(ascii_char([?-, ?+]))
    |> ascii_string([?0..?9], min: 1)
    |> reduce({:reduce_integer, []})

  integer_literal =
    integer_value
    |> unwrap_and_tag(:integer)

  boolean_literal =
    choice([
      string("true") |> replace(true),
      string("false") |> replace(false)
    ])
    |> unwrap_and_tag(:boolean)

  null_literal =
    string("null")
    |> replace(nil)
    |> unwrap_and_tag(:null)

  value = choice([string_literal, boolean_literal, null_literal, integer_literal])

  list_literal =
    ignore(string("["))
    |> concat(optional_ws)
    |> optional(
      value
      |> repeat(
        ignore(concat(optional_ws, string(",")))
        |> concat(optional_ws)
        |> concat(value)
      )
    )
    |> concat(optional_ws)
    |> ignore(string("]"))
    |> tag(:list)

  property_ref =
    identifier
    |> ignore(string("."))
    |> concat(identifier)
    |> tag(:property)

  comparison_op =
    choice([
      string(">=") |> replace(:gte),
      string("<=") |> replace(:lte),
      string("<>") |> replace(:neq),
      string("!=") |> replace(:neq),
      string("=") |> replace(:eq),
      string(">") |> replace(:gt),
      string("<") |> replace(:lt)
    ])

  where_comparison_condition =
    concat(optional_ws, property_ref)
    |> ignore(whitespace)
    |> concat(comparison_op)
    |> ignore(whitespace)
    |> concat(value)
    |> tag(:condition_cmp)

  null_not =
    string("NOT")
    |> ignore(whitespace)
    |> replace(true)

  where_null_condition =
    concat(optional_ws, property_ref)
    |> ignore(whitespace)
    |> ignore(string("IS"))
    |> ignore(whitespace)
    |> optional(null_not)
    |> ignore(string("NULL"))
    |> tag(:condition_null)

  bool_state =
    choice([
      string("TRUE") |> replace(true),
      string("FALSE") |> replace(false),
      string("true") |> replace(true),
      string("false") |> replace(false)
    ])

  where_bool_condition =
    concat(optional_ws, property_ref)
    |> ignore(whitespace)
    |> ignore(string("IS"))
    |> ignore(whitespace)
    |> optional(null_not)
    |> concat(bool_state)
    |> tag(:condition_bool)

  in_not =
    string("NOT")
    |> ignore(whitespace)
    |> replace(true)

  where_in_condition =
    concat(optional_ws, property_ref)
    |> ignore(whitespace)
    |> optional(in_not)
    |> ignore(string("IN"))
    |> ignore(whitespace)
    |> concat(list_literal)
    |> tag(:condition_in)

  between_not =
    string("NOT")
    |> ignore(whitespace)
    |> replace(true)

  where_between_condition =
    concat(optional_ws, property_ref)
    |> ignore(whitespace)
    |> optional(between_not)
    |> ignore(string("BETWEEN"))
    |> ignore(whitespace)
    |> concat(value)
    |> ignore(whitespace)
    |> ignore(string("AND"))
    |> ignore(whitespace)
    |> concat(value)
    |> tag(:condition_between)

  text_predicate_op =
    choice([
      string("CONTAINS") |> replace(:contains),
      string("STARTS") |> ignore(whitespace) |> ignore(string("WITH")) |> replace(:starts_with),
      string("ENDS") |> ignore(whitespace) |> ignore(string("WITH")) |> replace(:ends_with)
    ])

  where_text_condition =
    concat(optional_ws, property_ref)
    |> ignore(whitespace)
    |> concat(text_predicate_op)
    |> ignore(whitespace)
    |> concat(string_literal)
    |> tag(:condition_text)

  where_condition =
    choice([
      where_bool_condition,
      where_null_condition,
      where_between_condition,
      where_in_condition,
      where_text_condition,
      where_comparison_condition
    ])

  logical_operator =
    choice([
      string("AND") |> replace(:and),
      string("OR") |> replace(:or),
      string("XOR") |> replace(:xor)
    ])
    |> tag(:logical)

  where_group =
    ignore(string("("))
    |> concat(optional_ws)
    |> parsec(:where_expression_item)
    |> repeat(
      ignore(whitespace)
      |> concat(logical_operator)
      |> ignore(whitespace)
      |> parsec(:where_expression_item)
    )
    |> concat(optional_ws)
    |> ignore(string(")"))
    |> tag(:group)

  where_atom = choice([where_group, where_condition])

  where_not_atom =
    ignore(string("NOT"))
    |> ignore(whitespace)
    |> parsec(:where_expression_item)
    |> tag(:unary)

  where_expression_item = choice([where_not_atom, where_atom])

  defcombinatorp(:where_expression_item, where_expression_item)

  where_clause =
    ignore(string("WHERE"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(where_expression_item)
    |> repeat(
      ignore(whitespace)
      |> concat(logical_operator)
      |> ignore(whitespace)
      |> concat(where_expression_item)
    )
    |> tag(:where)

  filter_clause =
    ignore(string("FILTER"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(where_expression_item)
    |> repeat(
      ignore(whitespace)
      |> concat(logical_operator)
      |> ignore(whitespace)
      |> concat(where_expression_item)
    )
    |> tag(:filter)

  defcombinator(:where_clause, where_clause)
  defcombinator(:filter_clause, filter_clause)

  defp reduce_integer([sign, digits]) when is_integer(sign) do
    String.to_integer(<<sign>> <> digits)
  end

  defp reduce_integer([digits]) when is_binary(digits) do
    String.to_integer(digits)
  end
end
