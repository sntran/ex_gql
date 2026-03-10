defmodule OpenGQL.QueryBuilder do
  @moduledoc """
  Converts a parsed GQL AST into an `OpenGQL.Statement` containing plain SQL
  operations and their bound parameters.

  No Ecto dependency — returns `%OpenGQL.Statement{}` structs that can be
  executed against any SQL (SQLite) connection via `OpenGQL.execute/2`.

  ## Operation mapping

  | GQL clause(s)           | Statement type | SQL produced                    |
  |-------------------------|----------------|---------------------------------|
  | `MATCH … RETURN`        | `:select`      | `SELECT … FROM nodes [JOIN …]`  |
  | `CREATE …`              | `:insert`      | `INSERT INTO nodes / edges …`   |
  | `MATCH … SET`           | `:update`      | `UPDATE nodes SET … WHERE …`    |
  | `MATCH … DELETE`        | `:delete`      | `DELETE FROM nodes WHERE …`     |
  | `MATCH … DETACH DELETE` | `:delete`      | edge delete + node delete       |
  """

  alias OpenGQL.Statement

  @doc "Builds a `Statement` from the AST produced by `OpenGQL.Parser.parse/1`."
  def build([{:statement, clauses}]) do
    match_elements = get_path_elements(clauses, :match)
    create_elements = get_path_elements(clauses, :create)
    set_assignments = get_set_assignments(clauses)
    delete_vars = get_delete_vars(clauses, :delete)
    detach_delete_vars = get_delete_vars(clauses, :detach_delete)
    return_items = Keyword.get(clauses, :return, [])
    where_predicates = get_predicate_tokens(clauses, :where)
    filter_predicates = get_predicate_tokens(clauses, :filter)
    extra_predicates = merge_predicate_tokens(where_predicates, filter_predicates)
    order_items = get_order_items(clauses)
    limit_value = get_integer_clause(clauses, :limit)
    offset_value = get_integer_clause(clauses, :offset)
    skip_value = get_integer_clause(clauses, :skip)

    select_opts = %{
      conditions: extra_predicates,
      order_by: order_items,
      limit: limit_value,
      offset: offset_value || skip_value
    }

    cond do
      # MATCH + RETURN (pure select)
      match_elements != [] and return_items != [] and
          create_elements == [] and set_assignments == [] and
          delete_vars == [] and detach_delete_vars == [] ->
        build_select(match_elements, return_items, select_opts)

      # Compound MATCH + CREATE — not yet supported
      create_elements != [] and match_elements != [] ->
        raise ArgumentError,
              "compound MATCH + CREATE is not yet supported; use CREATE and MATCH as separate statements"

      # Pure CREATE
      create_elements != [] ->
        build_create(create_elements)

      # MATCH + SET
      set_assignments != [] ->
        build_update(match_elements, set_assignments, extra_predicates)

      # MATCH + DETACH DELETE
      detach_delete_vars != [] ->
        build_detach_delete(match_elements, extra_predicates)

      # MATCH + DELETE
      delete_vars != [] ->
        build_delete(match_elements, extra_predicates)

      # Fallback: select all nodes
      true ->
        build_select(match_elements, return_items, select_opts)
    end
  end

  # ── Helpers for extracting clause data ──────────────────────────────────────

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
        Enum.flat_map(assignments, fn
          {:assignment, [var, prop, {_type, val}]} -> [{var, prop, val}]
          _ -> []
        end)
    end
  end

  defp get_delete_vars(clauses, key) do
    case Keyword.get(clauses, key, []) do
      [] -> []
      vars_data -> for {:vars, var_list} <- vars_data, var <- var_list, do: var
    end
  end

  defp get_predicate_tokens(clauses, key) do
    clauses
    |> Keyword.get(key, [])
    |> parse_predicate_items()
  end

  defp parse_predicate_items(items) when is_list(items) do
    Enum.flat_map(items, &parse_predicate_item/1)
  end

  defp parse_predicate_item(item) do
    case item do
      {:condition_cmp, [{:property, [var, prop]}, op, {_type, val}]} ->
        [{:pred, {:cmp, var, prop, op, val}}]

      {:condition_null, [{:property, [var, prop]}, true]} ->
        [{:pred, {:null, var, prop, true}}]

      {:condition_null, [{:property, [var, prop]}]} ->
        [{:pred, {:null, var, prop, false}}]

      {:condition_bool, [{:property, [var, prop]}, state]} when is_boolean(state) ->
        [{:pred, {:bool_state, var, prop, state, false}}]

      {:condition_bool, [{:property, [var, prop]}, true, state]} when is_boolean(state) ->
        [{:pred, {:bool_state, var, prop, state, true}}]

      {:condition_in, [{:property, [var, prop]}, {:list, values}]} ->
        typed_values = for {_t, v} <- values, do: v
        [{:pred, {:in, var, prop, typed_values, false}}]

      {:condition_in, [{:property, [var, prop]}, true, {:list, values}]} ->
        typed_values = for {_t, v} <- values, do: v
        [{:pred, {:in, var, prop, typed_values, true}}]

      {:condition_between, [{:property, [var, prop]}, {_, low}, {_, high}]} ->
        [{:pred, {:between, var, prop, low, high, false}}]

      {:condition_between, [{:property, [var, prop]}, true, {_, low}, {_, high}]} ->
        [{:pred, {:between, var, prop, low, high, true}}]

      {:condition_text, [{:property, [var, prop]}, op, {:string, text}]} ->
        [{:pred, {:text, var, prop, op, text}}]

      {:group, inner_items} when is_list(inner_items) ->
        [{:group, parse_predicate_items(inner_items)}]

      {:unary, [inner_item]} ->
        [{:unary_not, parse_predicate_item(inner_item)}]

      {:logical, [op]} when op in [:and, :or] ->
        [{:op, op}]

      {:logical, [op]} when op == :xor ->
        [{:op, :xor}]

      _ -> []
    end
  end

  defp merge_predicate_tokens([], []), do: []
  defp merge_predicate_tokens(tokens, []), do: tokens
  defp merge_predicate_tokens([], tokens), do: tokens
  defp merge_predicate_tokens(left, right), do: left ++ [{:op, :and}] ++ right

  defp get_order_items(clauses) do
    clauses
    |> Keyword.get(:order_by, [])
    |> Enum.flat_map(fn
      {:order_item, [{:property, [var, prop]}, dir]} when dir in [:asc, :desc] ->
        [{var, prop, dir}]

      {:order_item, [{:property, [var, prop]}]} ->
        [{var, prop, :asc}]

      _ ->
        []
    end)
  end

  defp get_integer_clause(clauses, key) do
    case Keyword.get(clauses, key, []) do
      [v | _] when is_integer(v) -> v
      _ -> nil
    end
  end

  # ── Path parsing ──────────────────────────────────────────────────────────────

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
    normalized_pairs =
      case pairs do
        [:props | rest] -> rest
        other -> other
      end

    normalized_pairs
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [k, {_t, v}] when is_binary(k) -> [{k, v}]
      _ -> []
    end)
    |> Map.new()
  end

  # ── SELECT (MATCH + RETURN) ──────────────────────────────────────────────────

  defp build_select(elements, _return_items, opts) do
    nodes = for {:node, n} <- elements, do: n
    edges = for {:edge, e} <- elements, do: e

    case {nodes, edges} do
      {[], _} ->
        %Statement{
          type: :select,
          operations: [{"SELECT key, value FROM nodes", []}],
          ast_info: %{kind: :all}
        }

      {[node], []} ->
        build_single_node_select(node, opts)

      {[n1, n2], [edge]} ->
        build_path_select(n1, edge, n2, opts)

      {[n1, n2], []} ->
        build_cross_select(n1, n2, opts)

      _ ->
        raise ArgumentError,
              "unsupported MATCH pattern: #{length(nodes)} node(s) and #{length(edges)} edge(s). " <>
                "Supported patterns: single node, two-node path with one edge, two-node cross join."
    end
  end

  defp build_single_node_select(%{var: var, labels: labels, props: props}, opts) do
    {conditions, params} = node_conditions("n", labels, props)
    alias_map = variable_alias_map([{var, "n"}])
    {extra_condition_sql, extra_params} = predicate_expression(alias_map, opts.conditions)

    base_sql =
      "SELECT n.key, n.value FROM nodes AS n" <>
        where_clause(add_predicate_condition(conditions, extra_condition_sql))

    {sql, sql_params} =
      apply_select_modifiers(
        base_sql,
        params ++ extra_params,
        alias_map,
        opts.order_by,
        opts.limit,
        opts.offset
      )

    %Statement{
      type: :select,
      operations: [{sql, sql_params}],
      ast_info: %{kind: :single_node, labels: labels, props: props}
    }
  end

  defp build_path_select(
      %{var: n1_var, labels: n1_labels, props: n1_props},
         %{dir: dir, types: edge_types},
      %{var: n2_var, labels: n2_labels, props: n2_props},
         opts
       ) do
    join_sql =
      case dir do
        :right ->
          "INNER JOIN edges AS e ON e.source = n1.key " <>
            "INNER JOIN nodes AS n2 ON n2.key = e.target"

        :left ->
          "INNER JOIN edges AS e ON e.target = n1.key " <>
            "INNER JOIN nodes AS n2 ON n2.key = e.source"

        _ ->
          "INNER JOIN edges AS e ON (e.source = n1.key OR e.target = n1.key) " <>
            "INNER JOIN nodes AS n2 ON (n2.key = e.target OR n2.key = e.source) AND n2.key != n1.key"
      end

    {n1_conds, n1_params} = node_conditions("n1", n1_labels, n1_props)
    {edge_conds, edge_params} = edge_conditions(edge_types)
    {n2_conds, n2_params} = node_conditions("n2", n2_labels, n2_props)

    alias_map = variable_alias_map([{n1_var, "n1"}, {n2_var, "n2"}])
    {extra_cond_sql, extra_params} = predicate_expression(alias_map, opts.conditions)

    all_conditions = add_predicate_condition(n1_conds ++ edge_conds ++ n2_conds, extra_cond_sql)
    all_params = n1_params ++ edge_params ++ n2_params ++ extra_params

    base_sql =
      "SELECT n1.key AS n1_key, n1.value AS n1_value, " <>
        "n2.key AS n2_key, n2.value AS n2_value " <>
        "FROM nodes AS n1 #{join_sql}" <>
        where_clause(all_conditions)

    {sql, sql_params} =
      apply_select_modifiers(
        base_sql,
        all_params,
        alias_map,
        opts.order_by,
        opts.limit,
        opts.offset
      )

    %Statement{
      type: :select,
      operations: [{sql, sql_params}],
      ast_info: %{
        kind: :path,
        dir: dir,
        n1: %{labels: n1_labels, props: n1_props},
        edge_types: edge_types,
        n2: %{labels: n2_labels, props: n2_props}
      }
    }
  end

  defp build_cross_select(
         %{var: n1_var, labels: n1_labels, props: n1_props},
         %{var: n2_var, labels: n2_labels, props: n2_props},
         opts
       ) do
    {n1_conds, n1_params} = node_conditions("n1", n1_labels, n1_props)
    {n2_conds, n2_params} = node_conditions("n2", n2_labels, n2_props)
    alias_map = variable_alias_map([{n1_var, "n1"}, {n2_var, "n2"}])
    {extra_cond_sql, extra_params} = predicate_expression(alias_map, opts.conditions)

    all_conditions = add_predicate_condition(n1_conds ++ n2_conds, extra_cond_sql)
    all_params = n1_params ++ n2_params ++ extra_params

    base_sql =
      "SELECT n1.key AS n1_key, n1.value AS n1_value, " <>
        "n2.key AS n2_key, n2.value AS n2_value " <>
        "FROM nodes AS n1 CROSS JOIN nodes AS n2" <>
        where_clause(all_conditions)

    {sql, sql_params} =
      apply_select_modifiers(
        base_sql,
        all_params,
        alias_map,
        opts.order_by,
        opts.limit,
        opts.offset
      )

    %Statement{
      type: :select,
      operations: [{sql, sql_params}],
      ast_info: %{
        kind: :cross,
        n1: %{labels: n1_labels, props: n1_props},
        n2: %{labels: n2_labels, props: n2_props}
      }
    }
  end

  # ── CREATE ───────────────────────────────────────────────────────────────────

  defp build_create(elements) do
    nodes = for {:node, n} <- elements, n.var != nil, do: n
    edge_triples = extract_edge_triples(elements)

    if nodes == [] and edge_triples == [] do
      raise ArgumentError,
            "CREATE: pattern has no named nodes; assign a variable to each node, " <>
              "e.g. CREATE (a:Person) instead of CREATE (:Person)"
    end

    node_key_map = Map.new(nodes, fn n -> {n.var, build_node_key(n)} end)

    node_ops =
      Enum.map(nodes, fn node ->
        key = build_node_key(node)
        value = encode_props(node.props)
        {"INSERT INTO nodes (key, value) VALUES (?, ?) ON CONFLICT DO NOTHING", [key, value]}
      end)

    edge_ops =
      Enum.flat_map(edge_triples, fn edge ->
        # For :left edges the relationship runs target->source in the data model.
        # For :right and :both we use source->target order as written.
        {source_key, target_key} =
          case edge.dir do
            :left ->
              {Map.get(node_key_map, edge.target_var),
               Map.get(node_key_map, edge.source_var)}

            dir when dir in [:right, :both] ->
              {Map.get(node_key_map, edge.source_var),
               Map.get(node_key_map, edge.target_var)}
          end

        case {source_key, target_key} do
          {nil, _} ->
            raise ArgumentError,
                  "CREATE: source node variable #{inspect(edge.source_var)} not found in pattern"

          {_, nil} ->
            raise ArgumentError,
                  "CREATE: target node variable #{inspect(edge.target_var)} not found in pattern"

          {src, tgt} ->
            [
              {"INSERT INTO edges (source, target, rel) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
               [src, tgt, edge.rel]}
            ]
        end
      end)

    %Statement{type: :insert, operations: node_ops ++ edge_ops}
  end

  defp extract_edge_triples(elements), do: do_extract_edge_triples(elements, [])

  defp do_extract_edge_triples([], acc), do: Enum.reverse(acc)

  defp do_extract_edge_triples([{:node, n1}, {:edge, e}, {:node, n2} | rest], acc) do
    triple = %{source_var: n1.var, target_var: n2.var, rel: List.first(e.types), dir: e.dir}
    do_extract_edge_triples([{:node, n2} | rest], [triple | acc])
  end

  defp do_extract_edge_triples([_ | rest], acc), do: do_extract_edge_triples(rest, acc)

  # ── UPDATE (MATCH + SET) ──────────────────────────────────────────────────────

  defp build_update(match_elements, assignments, extra_match_conditions) do
    nodes = for {:node, n} <- match_elements, do: n

    primary_var =
      case nodes do
        [node | _] -> node.var
        [] -> nil
      end

    # Validate all assignments target the matched variable
    if primary_var != nil do
      Enum.each(assignments, fn {var, _prop, _val} ->
        if var != primary_var do
          raise ArgumentError,
                "SET targets variable #{inspect(var)} but MATCH binds #{inspect(primary_var)}; " <>
                  "only the matched variable can be updated"
        end
      end)
    end

    {where_conds, where_params} =
      case nodes do
        [node | _] -> node_conditions("n", node.labels, node.props)
        [] -> {[], []}
      end

    alias_map =
      case nodes do
        [node | _] -> variable_alias_map([{node.var, "n"}])
        [] -> %{}
      end

    {extra_cond_sql, extra_params} = predicate_expression(alias_map, extra_match_conditions)

    # Build: json_set(value, '$.prop1', ?, '$.prop2', ?, ...)
    {json_set_args, set_params} =
      Enum.reduce(assignments, {[], []}, fn {_var, prop, val}, {args, params} ->
        {args ++ ["'$.#{prop}'", "?"], params ++ [val]}
      end)

    set_expr = "json_set(value, #{Enum.join(json_set_args, ", ")})"
    sql =
      "UPDATE nodes AS n SET value = #{set_expr}" <>
        where_clause(add_predicate_condition(where_conds, extra_cond_sql))
    params = set_params ++ where_params ++ extra_params

    %Statement{type: :update, operations: [{sql, params}]}
  end

  # ── DELETE (MATCH + DELETE) ───────────────────────────────────────────────────

  defp build_delete(match_elements, extra_match_conditions) do
    nodes = for {:node, n} <- match_elements, do: n

    {where_conds, where_params} =
      case nodes do
        [node | _] -> node_conditions("n", node.labels, node.props)
        [] -> {[], []}
      end

    alias_map =
      case nodes do
        [node | _] -> variable_alias_map([{node.var, "n"}])
        [] -> %{}
      end

    {extra_cond_sql, extra_params} = predicate_expression(alias_map, extra_match_conditions)

    sql = "DELETE FROM nodes AS n" <> where_clause(add_predicate_condition(where_conds, extra_cond_sql))
    %Statement{type: :delete, operations: [{sql, where_params ++ extra_params}]}
  end

  defp build_detach_delete(match_elements, extra_match_conditions) do
    nodes = for {:node, n} <- match_elements, do: n

    {where_conds, where_params} =
      case nodes do
        [node | _] -> node_conditions("n", node.labels, node.props)
        [] -> {[], []}
      end

    alias_map =
      case nodes do
        [node | _] -> variable_alias_map([{node.var, "n"}])
        [] -> %{}
      end

    {extra_cond_sql, extra_params} = predicate_expression(alias_map, extra_match_conditions)
    final_conds = add_predicate_condition(where_conds, extra_cond_sql)
    final_params = where_params ++ extra_params

    subq = "(SELECT key FROM nodes AS n" <> where_clause(final_conds) <> ")"
    edge_sql = "DELETE FROM edges WHERE source IN #{subq} OR target IN #{subq}"
    node_sql = "DELETE FROM nodes AS n" <> where_clause(final_conds)

    # Edge delete runs first; the subquery params appear twice — once for
    # the `source IN` clause and once for the `target IN` clause.
    %Statement{
      type: :delete,
      operations: [
        {edge_sql, final_params ++ final_params},
        {node_sql, final_params}
      ]
    }
  end

  defp variable_alias_map(pairs) do
    pairs
    |> Enum.reject(fn {var, alias_name} -> is_nil(var) or is_nil(alias_name) end)
    |> Map.new()
  end

  defp add_predicate_condition(base_conditions, nil), do: base_conditions
  defp add_predicate_condition(base_conditions, extra_sql), do: base_conditions ++ ["(#{extra_sql})"]

  defp predicate_expression(_alias_map, []), do: {nil, []}

  defp predicate_expression(alias_map, tokens) do
    compiled =
      Enum.map(tokens, fn
        {:pred, pred} -> {:pred, compile_predicate(alias_map, pred)}
        {:group, group_tokens} -> {:pred, compile_group(alias_map, group_tokens)}
        {:unary_not, unary_tokens} -> {:pred, compile_not(alias_map, unary_tokens)}
        {:op, op} -> {:op, op}
      end)

    build_predicate_expression(compiled)
  end

  defp build_predicate_expression([{:pred, first_pred} | rest]) do
    fold_predicate_expression(first_pred, rest)
  end

  defp build_predicate_expression(_), do: raise(ArgumentError, "invalid predicate expression")

  defp fold_predicate_expression({lhs_sql, lhs_params}, []), do: {lhs_sql, lhs_params}

  defp fold_predicate_expression({lhs_sql, lhs_params}, [{:op, op}, {:pred, {rhs_sql, rhs_params}} | rest])
       when op in [:and, :or, :xor] do
    combined =
      case op do
        :and ->
          {"(#{lhs_sql} AND #{rhs_sql})", lhs_params ++ rhs_params}

        :or ->
          {"(#{lhs_sql} OR #{rhs_sql})", lhs_params ++ rhs_params}

        :xor ->
          {
            "(((#{lhs_sql}) OR (#{rhs_sql})) AND NOT ((#{lhs_sql}) AND (#{rhs_sql})))",
            lhs_params ++ rhs_params ++ lhs_params ++ rhs_params
          }
      end

    fold_predicate_expression(combined, rest)
  end

  defp fold_predicate_expression(_lhs, _rest) do
    raise ArgumentError, "invalid predicate token sequence"
  end

  defp compile_group(alias_map, group_tokens) do
    {group_sql, group_params} = predicate_expression(alias_map, group_tokens)
    {"(#{group_sql})", group_params}
  end

  defp compile_not(alias_map, unary_tokens) do
    {inner_sql, inner_params} = predicate_expression(alias_map, unary_tokens)
    {"NOT (#{inner_sql})", inner_params}
  end

  defp compile_predicate(alias_map, {:cmp, var, prop, op, value}) do
    alias_name = resolve_alias(alias_map, var)
    translate_condition(alias_name, prop, op, value)
  end

  defp compile_predicate(alias_map, {:null, var, prop, is_not}) do
    alias_name = resolve_alias(alias_map, var)
    field = "json_extract(#{alias_name}.value, '$.#{prop}')"

    if is_not do
      {"#{field} IS NOT NULL", []}
    else
      {"#{field} IS NULL", []}
    end
  end

  defp compile_predicate(alias_map, {:bool_state, var, prop, state, negate?}) do
    alias_name = resolve_alias(alias_map, var)
    field = "json_extract(#{alias_name}.value, '$.#{prop}')"

    case {state, negate?} do
      {true, false} ->
        {"#{field} = 1", []}

      {false, false} ->
        {"#{field} = 0", []}

      {true, true} ->
        {"(#{field} IS NULL OR #{field} = 0)", []}

      {false, true} ->
        {"(#{field} IS NULL OR #{field} = 1)", []}
    end
  end

  defp compile_predicate(alias_map, {:in, var, prop, values, negate?}) do
    alias_name = resolve_alias(alias_map, var)
    field = "json_extract(#{alias_name}.value, '$.#{prop}')"

    case values do
      [] ->
        if negate? do
          {"1 = 1", []}
        else
          {"1 = 0", []}
        end

      vals ->
        placeholders = List.duplicate("?", length(vals)) |> Enum.join(",")
        op = if negate?, do: "NOT IN", else: "IN"
        {"#{field} #{op} (#{placeholders})", vals}
    end
  end

  defp compile_predicate(alias_map, {:between, var, prop, low, high, negate?}) do
    alias_name = resolve_alias(alias_map, var)
    field = "json_extract(#{alias_name}.value, '$.#{prop}')"

    if negate? do
      {"#{field} NOT BETWEEN ? AND ?", [low, high]}
    else
      {"#{field} BETWEEN ? AND ?", [low, high]}
    end
  end

  defp compile_predicate(alias_map, {:text, var, prop, op, text})
       when op in [:contains, :starts_with, :ends_with] do
    alias_name = resolve_alias(alias_map, var)
    field = "json_extract(#{alias_name}.value, '$.#{prop}')"

    like_value =
      case op do
        :contains -> "%#{text}%"
        :starts_with -> "#{text}%"
        :ends_with -> "%#{text}"
      end

    {"#{field} LIKE ?", [like_value]}
  end

  defp resolve_alias(alias_map, var) do
    case Map.get(alias_map, var) do
      nil ->
        raise ArgumentError,
              "condition references unknown variable #{inspect(var)} in WHERE/FILTER"

      alias_name ->
        alias_name
    end
  end

  defp translate_condition(alias_name, prop, op, value) do
    field = "json_extract(#{alias_name}.value, '$.#{prop}')"

    case {op, value} do
      {:eq, nil} -> {"#{field} IS NULL", []}
      {:neq, nil} -> {"#{field} IS NOT NULL", []}
      {:eq, v} -> {"#{field} = ?", [v]}
      {:neq, v} -> {"#{field} != ?", [v]}
      {:gt, v} -> {"#{field} > ?", [v]}
      {:gte, v} -> {"#{field} >= ?", [v]}
      {:lt, v} -> {"#{field} < ?", [v]}
      {:lte, v} -> {"#{field} <= ?", [v]}
      _ -> raise ArgumentError, "unsupported comparison operator: #{inspect(op)}"
    end
  end

  defp apply_select_modifiers(base_sql, base_params, alias_map, order_items, limit_value, offset_value) do
    {order_sql, _} = build_order_by(alias_map, order_items)

    sql_with_order =
      case order_sql do
        "" -> base_sql
        _ -> base_sql <> " ORDER BY " <> order_sql
      end

    {sql_after_limit, params_after_limit} =
      if is_integer(limit_value) do
        {sql_with_order <> " LIMIT ?", base_params ++ [limit_value]}
      else
        {sql_with_order, base_params}
      end

    if is_integer(offset_value) do
      {sql_after_limit <> " OFFSET ?", params_after_limit ++ [offset_value]}
    else
      {sql_after_limit, params_after_limit}
    end
  end

  defp build_order_by(_alias_map, []), do: {"", []}

  defp build_order_by(alias_map, order_items) do
    sql_parts =
      Enum.map(order_items, fn {var, prop, dir} ->
        alias_name =
          case Map.get(alias_map, var) do
            nil -> raise ArgumentError, "ORDER BY references unknown variable #{inspect(var)}"
            val -> val
          end

        direction = if dir == :desc, do: "DESC", else: "ASC"
        "json_extract(#{alias_name}.value, '$.#{prop}') #{direction}"
      end)

    {Enum.join(sql_parts, ", "), []}
  end

  # ── SQL helpers ───────────────────────────────────────────────────────────────

  # Returns {[condition_string], [param_value]} for a node alias.
  # Labels are matched by position in the JSON key array ($[1], $[2], ...).
  # Nil property values use IS NULL rather than = ?, because SQL `= NULL` never matches.
  defp node_conditions(alias_name, labels, props) do
    label_conds =
      labels
      |> Enum.with_index(1)
      |> Enum.map(fn {label, idx} when is_binary(label) ->
        "json_extract(#{alias_name}.key, '$[#{idx}]') = ?"
      end)

    label_params = labels

    {prop_conds, prop_params} =
      Enum.reduce(props, {[], []}, fn {key, val}, {conds, params} ->
        if is_nil(val) do
          {conds ++ ["json_extract(#{alias_name}.value, '$.#{key}') IS NULL"], params}
        else
          {conds ++ ["json_extract(#{alias_name}.value, '$.#{key}') = ?"], params ++ [val]}
        end
      end)

    {label_conds ++ prop_conds, label_params ++ prop_params}
  end

  defp edge_conditions([]), do: {[], []}

  defp edge_conditions(types) do
    placeholders = List.duplicate("?", length(types)) |> Enum.join(",")
    {["e.rel IN (#{placeholders})"], types}
  end

  defp where_clause([]), do: ""
  defp where_clause(conds), do: " WHERE " <> Enum.join(conds, " AND ")

  # ── Node key / JSON encoding ──────────────────────────────────────────────────

  defp build_node_key(%{var: var, labels: [], props: props}) do
    name = Map.get(props, "name", var)
    encode_json_string(to_string(name))
  end

  defp build_node_key(%{var: var, labels: labels, props: props}) when labels != [] do
    name = Map.get(props, "name", var)
    encode_json_array([to_string(name) | labels])
  end

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
