defmodule OpenGQL.Parser do
  @moduledoc """
  NimbleParsec-based parser for the GQL pattern subset.
  """

  import NimbleParsec

  # ── Whitespace ─────────────────────────────────────────────────────────────────

  whitespace =
    ascii_string([?\s, ?\n, ?\r, ?\t], min: 1)
    |> label("whitespace")

  optional_ws =
    ascii_string([?\s, ?\n, ?\r, ?\t], min: 0)
    |> ignore()

  # ── Literals ───────────────────────────────────────────────────────────────────

  identifier =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})
    |> label("identifier")

  integer_value =
    optional(ascii_char([?-, ?+]))
    |> ascii_string([?0..?9], min: 1)
    |> reduce({:reduce_integer, []})
  match_clause = parsec({OpenGQL.Parser.Graph, :match_clause})
  create_clause = parsec({OpenGQL.Parser.Graph, :create_clause})
  set_clause = parsec({OpenGQL.Parser.Graph, :set_clause})
  delete_clause = parsec({OpenGQL.Parser.Graph, :delete_clause})

  # ── RETURN Clause ──────────────────────────────────────────────────────────────

  return_item = choice([string("*"), identifier])

  return_clause =
    ignore(string("RETURN"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(return_item)
    |> repeat(
      ignore(concat(optional_ws, string(",")))
      |> concat(optional_ws)
      |> concat(return_item)
    )
    |> tag(:return)

  # ── WHERE/FILTER Clauses ─────────────────────────────────────────────────────

  where_clause = parsec({OpenGQL.Parser.Predicate, :where_clause})
  filter_clause = parsec({OpenGQL.Parser.Predicate, :filter_clause})

  property_ref =
    identifier
    |> ignore(string("."))
    |> concat(identifier)
    |> tag(:property)

  # ── ORDER BY / LIMIT / OFFSET / SKIP / FINISH ───────────────────────────────

  order_direction =
    choice([
      string("ASC") |> replace(:asc),
      string("DESC") |> replace(:desc)
    ])

  order_item =
    concat(optional_ws, property_ref)
    |> optional(
      ignore(whitespace)
      |> concat(order_direction)
    )
    |> tag(:order_item)

  order_by_clause =
    ignore(string("ORDER"))
    |> ignore(whitespace)
    |> ignore(string("BY"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(order_item)
    |> repeat(
      ignore(concat(optional_ws, string(",")))
      |> concat(optional_ws)
      |> concat(order_item)
    )
    |> tag(:order_by)

  limit_clause =
    ignore(string("LIMIT"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(integer_value)
    |> tag(:limit)

  offset_clause =
    ignore(string("OFFSET"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(integer_value)
    |> tag(:offset)

  skip_clause =
    ignore(string("SKIP"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(integer_value)
    |> tag(:skip)

  finish_clause =
    ignore(string("FINISH"))
    |> replace(true)
    |> tag(:finish)

  # ── Full Statement ─────────────────────────────────────────────────────────────

  clause =
    choice([
      match_clause,
      create_clause,
      set_clause,
      delete_clause,
      return_clause,
      where_clause,
      filter_clause,
      order_by_clause,
      limit_clause,
      offset_clause,
      skip_clause,
      finish_clause
    ])

  statement =
    optional_ws
    |> concat(clause)
    |> repeat(
      ignore(whitespace)
      |> concat(optional_ws)
      |> concat(clause)
    )
    |> optional(ignore(concat(optional_ws, string(";"))))
    |> concat(optional_ws)
    |> tag(:statement)

  defparsec(:parse, statement)

  defp reduce_integer([sign, digits]) when is_integer(sign) do
    String.to_integer(<<sign>> <> digits)
  end

  defp reduce_integer([digits]) when is_binary(digits) do
    String.to_integer(digits)
  end
end
