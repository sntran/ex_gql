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

  string_literal =
    ignore(ascii_char([?"]))
    |> repeat(
      lookahead_not(ascii_char([?"]))
      |> utf8_char([])
    )
    |> reduce({List, :to_string, []})
    |> ignore(ascii_char([?"]))
    |> unwrap_and_tag(:string)

  integer_literal =
    optional(ascii_char([?-, ?+]))
    |> ascii_string([?0..?9], min: 1)
    |> reduce({:reduce_integer, []})
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

  # ── Properties ─────────────────────────────────────────────────────────────────

  property_pair =
    concat(optional_ws, identifier)
    |> ignore(concat(optional_ws, string(":")))
    |> concat(optional_ws)
    |> concat(value)

  properties =
    ignore(string("{"))
    |> concat(optional_ws)
    |> optional(
      property_pair
      |> repeat(
        ignore(concat(optional_ws, string(",")))
        |> concat(optional_ws)
        |> concat(property_pair)
      )
    )
    |> concat(optional_ws)
    |> ignore(string("}"))
    |> tag(:props)

  # ── Node Pattern ───────────────────────────────────────────────────────────────

  node_var = identifier |> tag(:var)

  node_labels =
    ignore(string(":"))
    |> concat(identifier)
    |> repeat(ignore(string(":")) |> concat(identifier))
    |> tag(:labels)

  node_pattern =
    ignore(string("("))
    |> concat(optional_ws)
    |> optional(
      lookahead_not(ascii_char([?:, ?{, ?)]))
      |> concat(node_var)
    )
    |> optional(node_labels)
    |> concat(optional_ws)
    |> optional(properties)
    |> concat(optional_ws)
    |> ignore(string(")"))
    |> tag(:node)

  # ── Edge Pattern ───────────────────────────────────────────────────────────────

  edge_var = identifier |> tag(:var)

  edge_types =
    ignore(string(":"))
    |> concat(identifier)
    |> repeat(ignore(string("|")) |> concat(identifier))
    |> tag(:types)

  edge_inner =
    optional(
      lookahead_not(ascii_char([?:, ?{, ?]]))
      |> concat(edge_var)
    )
    |> optional(edge_types)
    |> concat(optional_ws)
    |> optional(properties)

  right_edge =
    ignore(string("-["))
    |> concat(optional_ws)
    |> concat(edge_inner)
    |> concat(optional_ws)
    |> ignore(string("]->"))
    |> tag(:edge_right)

  left_edge =
    ignore(string("<-["))
    |> concat(optional_ws)
    |> concat(edge_inner)
    |> concat(optional_ws)
    |> ignore(string("]-"))
    |> tag(:edge_left)

  undirected_edge =
    ignore(string("-["))
    |> concat(optional_ws)
    |> concat(edge_inner)
    |> concat(optional_ws)
    |> ignore(string("]-"))
    |> tag(:edge_undirected)

  # ── Path Pattern ───────────────────────────────────────────────────────────────

  path_pattern =
    node_pattern
    |> repeat(
      choice([right_edge, left_edge, undirected_edge])
      |> concat(node_pattern)
    )
    |> tag(:path)

  # ── MATCH Clause ───────────────────────────────────────────────────────────────

  match_clause =
    ignore(string("MATCH"))
    |> ignore(concat(whitespace, optional_ws))
    |> concat(path_pattern)
    |> repeat(
      ignore(concat(optional_ws, string(",")))
      |> concat(optional_ws)
      |> concat(path_pattern)
    )
    |> tag(:match)

  # ── CREATE Clause ──────────────────────────────────────────────────────────────

  create_clause =
    ignore(string("CREATE"))
    |> ignore(concat(whitespace, optional_ws))
    |> concat(path_pattern)
    |> repeat(
      ignore(concat(optional_ws, string(",")))
      |> concat(optional_ws)
      |> concat(path_pattern)
    )
    |> tag(:create)

  # ── SET Clause ─────────────────────────────────────────────────────────────────

  set_assignment =
    concat(optional_ws, identifier)
    |> ignore(string("."))
    |> concat(identifier)
    |> ignore(concat(optional_ws, string("=")))
    |> concat(optional_ws)
    |> concat(value)
    |> tag(:assignment)

  set_clause =
    ignore(string("SET"))
    |> ignore(whitespace)
    |> concat(optional_ws)
    |> concat(set_assignment)
    |> repeat(
      ignore(concat(optional_ws, string(",")))
      |> concat(optional_ws)
      |> concat(set_assignment)
    )
    |> tag(:set)

  # ── DELETE Clause ──────────────────────────────────────────────────────────────

  delete_vars =
    identifier
    |> repeat(
      ignore(concat(optional_ws, string(",")))
      |> concat(optional_ws)
      |> concat(identifier)
    )
    |> tag(:vars)

  delete_clause =
    choice([
      ignore(string("DETACH"))
      |> ignore(whitespace)
      |> ignore(string("DELETE"))
      |> ignore(whitespace)
      |> concat(optional_ws)
      |> concat(delete_vars)
      |> tag(:detach_delete),
      ignore(string("DELETE"))
      |> ignore(whitespace)
      |> concat(optional_ws)
      |> concat(delete_vars)
      |> tag(:delete)
    ])

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

  # ── Full Statement ─────────────────────────────────────────────────────────────

  clause =
    choice([
      match_clause,
      create_clause,
      set_clause,
      delete_clause,
      return_clause
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
