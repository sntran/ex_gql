defmodule OpenGQL.QueryBuilder do
  @moduledoc """
  Converts a parsed GQL AST into an `Ecto.Query`.

  Supports single-node queries, two-node path queries with a directed or
  undirected edge, and two separate (comma-separated) node patterns.
  """

  import Ecto.Query

  @doc """
  Builds an `Ecto.Query` from a parsed GQL AST produced by `OpenGQL.Parser`.
  """
  def build([{:statement, clauses}]) do
    match_elements = Keyword.get(clauses, :match, [])
    return_items = Keyword.get(clauses, :return, [])

    paths = for {:path, elements} <- match_elements, do: elements
    elements = Enum.flat_map(paths, &parse_path/1)

    build_from_elements(elements, return_items)
  end

  # ── Path parsing ───────────────────────────────────────────────────────────────

  defp parse_path(elements) do
    Enum.map(elements, fn
      {:node, attrs} ->
        {:node,
         %{
           var: extract_head(attrs, :var),
           labels: Keyword.get(attrs, :labels, []),
           props: build_props(Keyword.get(attrs, :props, []))
         }}

      {:edge_right, attrs} ->
        {:edge, %{dir: :right, types: Keyword.get(attrs, :types, [])}}

      {:edge_left, attrs} ->
        {:edge, %{dir: :left, types: Keyword.get(attrs, :types, [])}}

      {:edge_undirected, attrs} ->
        {:edge, %{dir: :both, types: Keyword.get(attrs, :types, [])}}
    end)
  end

  defp extract_head(attrs, key) do
    case Keyword.get(attrs, key) do
      nil -> nil
      [v | _] -> v
    end
  end

  defp build_props([]), do: %{}

  defp build_props(pairs) do
    pairs
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [k, {_t, v}] when is_binary(k) -> [{k, v}]
      _ -> []
    end)
    |> Map.new()
  end

  # ── Query building ─────────────────────────────────────────────────────────────

  defp build_from_elements(elements, _return_items) do
    nodes = for {:node, n} <- elements, do: n
    edges = for {:edge, e} <- elements, do: e

    case {nodes, edges} do
      {[], _} ->
        from(n in "nodes", select: n)

      {[node], []} ->
        build_single_node_query(node)

      {[n1, n2], [edge]} ->
        build_path_query(n1, edge, n2)

      {[n1, n2], []} ->
        build_cross_query(n1, n2)

      _ ->
        from(n in "nodes", select: n)
    end
  end

  defp build_single_node_query(%{labels: labels, props: props}) do
    q = from(n in "nodes")

    q =
      Enum.reduce(labels, q, fn label, acc ->
        from(n in acc, where: fragment("json_extract(?, '$[1]') = ?", n.key, ^label))
      end)

    q =
      Enum.reduce(props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        from(n in acc, where: fragment("json_extract(?, ?) = ?", n.value, ^path, ^val))
      end)

    from(n in q, select: n)
  end

  defp build_path_query(
         %{labels: n1_labels, props: n1_props},
         %{dir: dir, types: edge_types},
         %{labels: n2_labels, props: n2_props}
       ) do
    q = from(n1 in "nodes", as: :n1)

    q =
      case dir do
        :right ->
          q
          |> join(:inner, [n1: n1], e in "edges", as: :e, on: e.source == n1.key)
          |> join(:inner, [e: e], n2 in "nodes", as: :n2, on: n2.key == e.target)

        :left ->
          q
          |> join(:inner, [n1: n1], e in "edges", as: :e, on: e.target == n1.key)
          |> join(:inner, [e: e], n2 in "nodes", as: :n2, on: n2.key == e.source)

        _ ->
          q
          |> join(:inner, [n1: n1], e in "edges",
            as: :e,
            on: e.source == n1.key or e.target == n1.key
          )
          |> join(:inner, [e: e], n2 in "nodes",
            as: :n2,
            on: n2.key == e.target or n2.key == e.source
          )
      end

    q =
      Enum.reduce(n1_labels, q, fn label, acc ->
        where(acc, [n1: n1], fragment("json_extract(?, '$[1]') = ?", n1.key, ^label))
      end)

    q =
      Enum.reduce(n1_props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n1: n1], fragment("json_extract(?, ?) = ?", n1.value, ^path, ^val))
      end)

    q =
      Enum.reduce(edge_types, q, fn type, acc ->
        where(acc, [e: e], e.rel == ^type)
      end)

    q =
      Enum.reduce(n2_labels, q, fn label, acc ->
        where(acc, [n2: n2], fragment("json_extract(?, '$[1]') = ?", n2.key, ^label))
      end)

    q =
      Enum.reduce(n2_props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n2: n2], fragment("json_extract(?, ?) = ?", n2.value, ^path, ^val))
      end)

    from([n1: n1, n2: n2] in q, select: {n1, n2})
  end

  defp build_cross_query(
         %{labels: n1_labels, props: n1_props},
         %{labels: n2_labels, props: n2_props}
       ) do
    q = from(n1 in "nodes", as: :n1, cross_join: n2 in "nodes", as: :n2)

    q =
      Enum.reduce(n1_labels, q, fn label, acc ->
        where(acc, [n1: n1], fragment("json_extract(?, '$[1]') = ?", n1.key, ^label))
      end)

    q =
      Enum.reduce(n1_props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n1: n1], fragment("json_extract(?, ?) = ?", n1.value, ^path, ^val))
      end)

    q =
      Enum.reduce(n2_labels, q, fn label, acc ->
        where(acc, [n2: n2], fragment("json_extract(?, '$[1]') = ?", n2.key, ^label))
      end)

    q =
      Enum.reduce(n2_props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n2: n2], fragment("json_extract(?, ?) = ?", n2.value, ^path, ^val))
      end)

    from([n1: n1, n2: n2] in q, select: {n1, n2})
  end
end
