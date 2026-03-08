defmodule OpenGQL.QueryBuilder do
  @moduledoc """
  Converts a parsed GQL AST into Ecto operations.

  Returns:
  - `Ecto.Query` for MATCH+RETURN (SELECT)
  - `Ecto.Multi` for CREATE
  - `{:delete, Ecto.Query}` for MATCH+DELETE
  - `{:update, Ecto.Query, assignments}` for MATCH+SET
  """

  import Ecto.Query

  alias OpenGQL.Schema.Node
  alias OpenGQL.Schema.Edge

  def build([{:statement, clauses}]) do
    match_elements = get_path_elements(clauses, :match)
    create_elements = get_path_elements(clauses, :create)
    set_assignments = get_set_assignments(clauses)
    delete_vars = get_delete_vars(clauses, :delete)
    detach_delete_vars = get_delete_vars(clauses, :detach_delete)
    return_items = Keyword.get(clauses, :return, [])

    cond do
      # MATCH + RETURN (pure select)
      match_elements != [] and return_items != [] and
          create_elements == [] and set_assignments == [] and
          delete_vars == [] and detach_delete_vars == [] ->
        build_select(match_elements, return_items)

      # CREATE without MATCH
      create_elements != [] and match_elements == [] ->
        build_create(create_elements)

      # MATCH + CREATE
      create_elements != [] and match_elements != [] ->
        build_match_create(match_elements, create_elements)

      # MATCH + SET
      set_assignments != [] ->
        build_update(match_elements, set_assignments)

      # MATCH + DELETE or DETACH DELETE
      delete_vars != [] or detach_delete_vars != [] ->
        vars = delete_vars ++ detach_delete_vars
        build_delete(match_elements, vars)

      # Fallback to select
      true ->
        build_select(match_elements, return_items)
    end
  end

  # ── Helpers for extracting clause data ────────────────────────────────────────

  defp get_path_elements(clauses, key) do
    case Keyword.get(clauses, key, []) do
      [] ->
        []

      elements ->
        paths = for {:path, path_elems} <- elements, do: path_elems
        Enum.flat_map(paths, &parse_path/1)
    end
  end

  defp get_set_assignments(clauses) do
    case Keyword.get(clauses, :set, []) do
      [] ->
        []

      assignments ->
        assignments
        |> Enum.flat_map(fn
          {:assignment, [var, prop, {_type, val}]} -> [{var, prop, val}]
          _ -> []
        end)
    end
  end

  defp get_delete_vars(clauses, key) do
    case Keyword.get(clauses, key, []) do
      [] ->
        []

      vars_data ->
        for {:vars, var_list} <- vars_data, var <- var_list, do: var
    end
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
        {:edge,
         %{
           dir: :right,
           types: Keyword.get(attrs, :types, []),
           props: build_props(Keyword.get(attrs, :props, []))
         }}

      {:edge_left, attrs} ->
        {:edge,
         %{
           dir: :left,
           types: Keyword.get(attrs, :types, []),
           props: build_props(Keyword.get(attrs, :props, []))
         }}

      {:edge_undirected, attrs} ->
        {:edge,
         %{
           dir: :both,
           types: Keyword.get(attrs, :types, []),
           props: build_props(Keyword.get(attrs, :props, []))
         }}
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

  # ── SELECT (MATCH + RETURN) ────────────────────────────────────────────────────

  defp build_select(elements, _return_items) do
    nodes = for {:node, n} <- elements, do: n
    edges = for {:edge, e} <- elements, do: e

    case {nodes, edges} do
      {[], _} -> from(n in Node, select: n)
      {[node], []} -> build_single_node_query(node)
      {[n1, n2], [edge]} -> build_path_query(n1, edge, n2)
      {[n1, n2], []} -> build_cross_query(n1, n2)
      _ -> from(n in Node, select: n)
    end
  end

  defp build_single_node_query(%{labels: labels, props: props}) do
    q = from(n in Node)

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
    q = from(n1 in Node, as: :n1)

    q =
      case dir do
        :right ->
          q
          |> join(:inner, [n1: n1], e in Edge, as: :e, on: e.source == n1.key)
          |> join(:inner, [e: e], n2 in Node, as: :n2, on: n2.key == e.target)

        :left ->
          q
          |> join(:inner, [n1: n1], e in Edge, as: :e, on: e.target == n1.key)
          |> join(:inner, [e: e], n2 in Node, as: :n2, on: n2.key == e.source)

        _ ->
          q
          |> join(:inner, [n1: n1], e in Edge,
            as: :e,
            on: e.source == n1.key or e.target == n1.key
          )
          |> join(:inner, [e: e], n2 in Node,
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
    q = from(n1 in Node, as: :n1, cross_join: n2 in Node, as: :n2)

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

  # ── CREATE ─────────────────────────────────────────────────────────────────────

  defp build_create(elements) do
    {nodes, edges} = extract_nodes_and_edges(elements)
    multi = Ecto.Multi.new()
    multi = insert_nodes_into_multi(multi, nodes)
    multi = insert_edges_into_multi(multi, edges, nodes)
    multi
  end

  defp build_match_create(_match_elements, create_elements) do
    build_create(create_elements)
  end

  defp extract_nodes_and_edges(elements) do
    nodes = for {:node, n} <- elements, n.var != nil, do: n
    edges = extract_edge_triples(elements)
    {nodes, edges}
  end

  defp extract_edge_triples(elements) do
    extract_edge_triples(elements, [])
  end

  defp extract_edge_triples([], acc), do: Enum.reverse(acc)

  defp extract_edge_triples([{:node, n1}, {:edge, e}, {:node, n2} | rest], acc) do
    edge_info = %{
      source_var: n1.var,
      target_var: n2.var,
      rel: List.first(e.types),
      dir: e.dir
    }

    extract_edge_triples([{:node, n2} | rest], [edge_info | acc])
  end

  defp extract_edge_triples([_ | rest], acc), do: extract_edge_triples(rest, acc)

  defp insert_nodes_into_multi(multi, nodes) do
    Enum.reduce(nodes, multi, fn node, m ->
      key = build_node_key(node)
      value = encode_props(node.props)
      struct = %Node{key: key, value: value}
      Ecto.Multi.insert(m, {:node, node.var}, struct, on_conflict: :nothing)
    end)
  end

  defp build_node_key(%{var: var, labels: [], props: props}) do
    name = Map.get(props, "name", var)
    encode_json_string(to_string(name))
  end

  defp build_node_key(%{var: var, labels: [label | _], props: props}) do
    name = Map.get(props, "name", var)
    encode_json_array([to_string(name), label])
  end

  defp insert_edges_into_multi(multi, edges, nodes) do
    node_key_map = Map.new(nodes, fn n -> {n.var, build_node_key(n)} end)

    Enum.reduce(Enum.with_index(edges), multi, fn {edge, idx}, m ->
      {source_key, target_key} =
        case edge.dir do
          :left ->
            {Map.get(node_key_map, edge.target_var), Map.get(node_key_map, edge.source_var)}

          _ ->
            {Map.get(node_key_map, edge.source_var), Map.get(node_key_map, edge.target_var)}
        end

      if source_key && target_key do
        struct = %Edge{
          source: source_key,
          target: target_key,
          rel: edge.rel
        }

        Ecto.Multi.insert(m, {:edge, idx}, struct, on_conflict: :nothing)
      else
        m
      end
    end)
  end

  # ── UPDATE (SET) ───────────────────────────────────────────────────────────────

  defp build_update(match_elements, assignments) do
    nodes = for {:node, n} <- match_elements, do: n

    base_query =
      case nodes do
        [node | _] -> build_single_node_query_no_select(node)
        [] -> from(n in Node)
      end

    {:update, base_query, assignments}
  end

  defp build_single_node_query_no_select(%{labels: labels, props: props}) do
    q = from(n in Node)

    q =
      Enum.reduce(labels, q, fn label, acc ->
        from(n in acc, where: fragment("json_extract(?, '$[1]') = ?", n.key, ^label))
      end)

    Enum.reduce(props, q, fn {key, val}, acc ->
      path = "$.#{key}"
      from(n in acc, where: fragment("json_extract(?, ?) = ?", n.value, ^path, ^val))
    end)
  end

  # ── DELETE ─────────────────────────────────────────────────────────────────────

  defp build_delete(match_elements, _vars) do
    nodes = for {:node, n} <- match_elements, do: n

    base_query =
      case nodes do
        [node | _] -> build_single_node_query_no_select(node)
        [] -> from(n in Node)
      end

    {:delete, base_query}
  end

  # ── JSON encoding helpers ──────────────────────────────────────────────────────

  defp encode_json_string(s) when is_binary(s) do
    escaped =
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")
      |> String.replace("\b", "\\b")
      |> String.replace("\f", "\\f")

    "\"#{escaped}\""
  end

  defp encode_json_array(items) do
    "[#{Enum.map_join(items, ",", &encode_json_string/1)}]"
  end

  defp encode_props(props) when is_map(props) and map_size(props) == 0, do: "{}"

  defp encode_props(props) do
    pairs =
      Enum.map_join(props, ",", fn {k, v} ->
        "#{encode_json_string(k)}:#{encode_value(v)}"
      end)

    "{#{pairs}}"
  end

  defp encode_value(v) when is_binary(v), do: encode_json_string(v)
  defp encode_value(v) when is_integer(v), do: Integer.to_string(v)
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(nil), do: "null"
end
