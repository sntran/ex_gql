defimpl Ecto.Queryable, for: OpenGQL.Statement do
  @moduledoc """
  `Ecto.Queryable` implementation for `OpenGQL.Statement`.

  Allows passing a SELECT-type `%OpenGQL.Statement{}` directly to Ecto repo
  operations such as `Repo.all/2`:

      stmt = ~G"MATCH (a:Person {name: \\"Alice\\"}) RETURN a"
      results = Repo.all(stmt)
      # results => [%{"key" => "...", "value" => "..."}]

  Only `:select` (MATCH … RETURN) statements are supported.  Passing a
  `:insert`, `:update`, or `:delete` statement will raise an `ArgumentError`.

  ## Return format

  Results from `Repo.all/2` match the string-keyed maps returned by
  `OpenGQL.execute/2`:

  | Query type       | Map keys                                       |
  |------------------|------------------------------------------------|
  | Single node      | `"key"`, `"value"`                             |
  | Path / cross     | `"n1_key"`, `"n1_value"`, `"n2_key"`, `"n2_value"` |
  """

  import Ecto.Query

  # ── All nodes (no MATCH conditions) ─────────────────────────────────────────

  def to_query(%OpenGQL.Statement{type: :select, ast_info: %{kind: :all}}) do
    from(n in "nodes", select: %{"key" => n.key, "value" => n.value})
  end

  # ── Single node (optional label + property conditions) ──────────────────────

  def to_query(%OpenGQL.Statement{
        type: :select,
        ast_info: %{kind: :single_node, labels: labels, props: props}
      }) do
    q = from(n in "nodes")

    q =
      Enum.reduce(labels, q, fn label, acc ->
        where(acc, [n], fragment("json_extract(?, '$[1]') = ?", n.key, ^label))
      end)

    q =
      Enum.reduce(props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n], fragment("json_extract(?, ?) = ?", n.value, ^path, ^val))
      end)

    select(q, [n], %{"key" => n.key, "value" => n.value})
  end

  # ── Path query (directed or undirected edge) ─────────────────────────────────

  def to_query(%OpenGQL.Statement{
        type: :select,
        ast_info: %{kind: :path, dir: dir, n1: n1_info, edge_types: edge_types, n2: n2_info}
      }) do
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
          |> join(:inner, [e: e, n1: n1], n2 in "nodes",
            as: :n2,
            on: (n2.key == e.target or n2.key == e.source) and n2.key != n1.key
          )
      end

    q =
      Enum.reduce(n1_info.labels, q, fn label, acc ->
        where(acc, [n1: n1], fragment("json_extract(?, '$[1]') = ?", n1.key, ^label))
      end)

    q =
      Enum.reduce(n1_info.props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n1: n1], fragment("json_extract(?, ?) = ?", n1.value, ^path, ^val))
      end)

    q =
      Enum.reduce(edge_types, q, fn type, acc ->
        where(acc, [e: e], e.rel == ^type)
      end)

    q =
      Enum.reduce(n2_info.labels, q, fn label, acc ->
        where(acc, [n2: n2], fragment("json_extract(?, '$[1]') = ?", n2.key, ^label))
      end)

    q =
      Enum.reduce(n2_info.props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n2: n2], fragment("json_extract(?, ?) = ?", n2.value, ^path, ^val))
      end)

    select(q, [n1: n1, n2: n2], %{
      "n1_key" => n1.key,
      "n1_value" => n1.value,
      "n2_key" => n2.key,
      "n2_value" => n2.value
    })
  end

  # ── Cross join (two nodes, no edge) ──────────────────────────────────────────

  def to_query(%OpenGQL.Statement{
        type: :select,
        ast_info: %{kind: :cross, n1: n1_info, n2: n2_info}
      }) do
    q =
      from(n1 in "nodes",
        as: :n1,
        cross_join: n2 in "nodes",
        as: :n2
      )

    q =
      Enum.reduce(n1_info.labels, q, fn label, acc ->
        where(acc, [n1: n1], fragment("json_extract(?, '$[1]') = ?", n1.key, ^label))
      end)

    q =
      Enum.reduce(n1_info.props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n1: n1], fragment("json_extract(?, ?) = ?", n1.value, ^path, ^val))
      end)

    q =
      Enum.reduce(n2_info.labels, q, fn label, acc ->
        where(acc, [n2: n2], fragment("json_extract(?, '$[1]') = ?", n2.key, ^label))
      end)

    q =
      Enum.reduce(n2_info.props, q, fn {key, val}, acc ->
        path = "$.#{key}"
        where(acc, [n2: n2], fragment("json_extract(?, ?) = ?", n2.value, ^path, ^val))
      end)

    select(q, [n1: n1, n2: n2], %{
      "n1_key" => n1.key,
      "n1_value" => n1.value,
      "n2_key" => n2.key,
      "n2_value" => n2.value
    })
  end

  # ── Unsupported statement types ───────────────────────────────────────────────

  def to_query(%OpenGQL.Statement{type: type}) do
    raise ArgumentError,
          "Ecto.Queryable is only implemented for SELECT (:select) statements, " <>
            "got #{inspect(type)}. Use OpenGQL.execute/2 for INSERT, UPDATE, and DELETE."
  end
end
