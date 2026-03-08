defmodule OpenGQL.Parser do
  @moduledoc """
  NimbleParsec-based parser for the GQL MATCH pattern subset.

  Supports parsing:
  - Node patterns: `(variable:Label {props})`
  - Edge patterns: `-[:TYPE]->`, `<-[:TYPE]-`
  - Path patterns: `(a:Label)-[:TYPE]->(b:Label)`
  - MATCH clause with multiple comma-separated patterns
  - RETURN clause

  ## Examples

      iex> OpenGQL.Parser.parse("MATCH (a:Person) RETURN a")
      {:ok, [{:statement, [match: [path: [node: [var: ["a"], labels: ["Person"]]]], return: ["a"]]}], "", %{}, {1, 0}, 25}

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

  # `-[...]->`
  right_edge =
    ignore(string("-["))
    |> concat(optional_ws)
    |> concat(edge_inner)
    |> concat(optional_ws)
    |> ignore(string("]->"))
    |> tag(:edge_right)

  # `<-[...]-`
  left_edge =
    ignore(string("<-["))
    |> concat(optional_ws)
    |> concat(edge_inner)
    |> concat(optional_ws)
    |> ignore(string("]-"))
    |> tag(:edge_left)

  # `-[...]-` (undirected)
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

  statement =
    concat(optional_ws, match_clause)
    |> ignore(whitespace)
    |> concat(return_clause)
    |> optional(ignore(concat(optional_ws, string(";"))))
    |> concat(optional_ws)
    |> tag(:statement)

  defparsec(:parse, statement)

  # ── Helpers ────────────────────────────────────────────────────────────────────

  defp reduce_integer([sign, digits]) when is_integer(sign) do
    String.to_integer(<<sign>> <> digits)
  end

  defp reduce_integer([digits]) when is_binary(digits) do
    String.to_integer(digits)
  end
end
