defmodule OpenGQL do
  @moduledoc ~S"""
  An Elixir library for querying a SQLite graph database using a subset of
  the [Open Graph Query Language (GQL)](https://www.iso.org/standard/76120.html).

  OpenGQL is **Ecto-free at the library level**: it has no Ecto runtime
  dependency and produces plain SQL statements that can be executed against
  any SQLite-compatible connection.  Tests and your application code may
  still use Ecto — `OpenGQL.execute/2` accepts any 2-arity function that runs
  a SQL query, including `&MyRepo.query/2`.

  ## Data Model

  OpenGQL targets the following SQLite graph schema:

      CREATE TABLE nodes (
        key   TEXT PRIMARY KEY NOT NULL,  -- JSON: string or ["id", "Label"]
        value TEXT                        -- JSON: property map
      );

      CREATE TABLE edges (
        source TEXT REFERENCES nodes(key),
        target TEXT REFERENCES nodes(key),
        rel    TEXT,   -- relationship type
        value  TEXT    -- JSON: edge properties
      );

  ## Sigils

  The `~GQL` sigil (Elixir ≥ 1.15) and the `~G` alias (Elixir 1.14) parse a
  GQL string and return an `%OpenGQL.Statement{}`:

      import OpenGQL

      stmt = ~G[MATCH (a:Person {name: "Alice"}) RETURN a]
      #=> %OpenGQL.Statement{type: :select, operations: [{"SELECT ...", [...]}]}

  ## Executing statements

  ### Via `OpenGQL.execute/2` (adapter-agnostic)

  Pass the statement and a SQL query function to `execute/2`:

      {:ok, rows} = OpenGQL.execute(stmt, &MyRepo.query/2)
      # rows => [%{"key" => "[\"alice\",\"Person\"]", "value" => "{\"name\":\"Alice\"}"}]

  ### Via `Repo.all/2` (Ecto.Queryable)

  SELECT statements implement the `Ecto.Queryable` protocol when the
  `test/support/queryable.ex` protocol implementation is compiled (available
  in `:test` and `:dev` environments — see `mix.exs` `elixirc_paths`).  This
  lets you pass a statement directly to any Ecto repo operation:

      results = Repo.all(~G"MATCH (a:Person) RETURN a")
      # returns the same string-keyed maps as execute/2

  ## Supported GQL clauses

  | Clause(s)               | Statement type  | Repo usage                    |
  |-------------------------|-----------------|-------------------------------|
  | `MATCH … RETURN`        | `:select`       | `execute/2` → list of row maps|
  | `WHERE` / `FILTER`      | `:select`       | SELECT predicate modifiers    |
  | `ORDER BY`              | `:select`       | SELECT ordering modifier      |
  | `LIMIT` / `OFFSET` / `SKIP` | `:select`   | SELECT pagination modifiers   |
  | `FINISH`                | `:select`       | terminal marker (no-op)       |
  | `CREATE …`              | `:insert`       | `execute/2` → `{:ok, results}`|
  | `MATCH … SET`           | `:update`       | `execute/2` → `{:ok, result}` |
  | `MATCH … DELETE`        | `:delete`       | `execute/2` → `{:ok, result}` |
  | `MATCH … DETACH DELETE` | `:delete`       | `execute/2` → `{:ok, results}`|

  ## Examples

      import OpenGQL

      # --- MATCH + RETURN ---
      stmt = ~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b"
      {:ok, rows} = OpenGQL.execute(stmt, &MyRepo.query/2)

      # --- CREATE ---
      stmt = ~G'CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})'
      {:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

      # --- MATCH + SET ---
      stmt = ~G"MATCH (a:Person) SET a.active = true"
      {:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

      # --- MATCH + DELETE ---
      stmt = ~G"MATCH (a:Person) DELETE a"
      {:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

      # --- MATCH + DETACH DELETE ---
      stmt = ~G"MATCH (a:Person) DETACH DELETE a"
      {:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

  """

  alias OpenGQL.Parser
  alias OpenGQL.QueryBuilder
  alias OpenGQL.Statement

  @parser_module Parser

  @doc ~S"""
  `~GQL` sigil — compiles a GQL string into an `%OpenGQL.Statement{}`.

  Requires Elixir >= 1.15 for the multi-character sigil syntax.
  On Elixir 1.14 use the `~G` alias defined in this module.

  ## Examples

      iex> import OpenGQL
      iex> stmt = ~G"MATCH (a:Person) RETURN a"
      iex> %OpenGQL.Statement{type: :select} = stmt
      iex> is_struct(stmt, OpenGQL.Statement)
      true

  """
  defmacro sigil_GQL(term, _modifiers) do
    quote do
      unquote(term)
      |> OpenGQL.parse_and_build()
    end
  end

  @doc """
  `~G` sigil — single-character alias for `~GQL`, available on Elixir 1.14+.
  """
  defmacro sigil_G(term, _modifiers) do
    quote do
      unquote(term)
      |> OpenGQL.parse_and_build()
    end
  end

  @doc """
  Parses a GQL string and builds the corresponding `%OpenGQL.Statement{}`.

  Raises `ArgumentError` if the GQL string is invalid.
  """
  def parse_and_build(gql_string) when is_binary(gql_string) do
    parse_and_build(gql_string, @parser_module)
  end

  @doc false
  def parse_and_build(gql_string, parser_module)
      when is_binary(gql_string) and is_atom(parser_module) do
    gql_string = String.trim(gql_string)

    case parser_module.parse(gql_string) do
      {:ok, ast, "", _ctx, _line, _offset} ->
        QueryBuilder.build(ast)

      {:ok, _ast, rest, _ctx, _line, _offset} ->
        raise ArgumentError, "GQL parse error: unexpected input near #{inspect(rest)}"

      {:error, reason, rest, _ctx, _line, _offset} ->
        if String.contains?(to_string(reason), "{:illegal,") do
          unexpected = if rest == "", do: gql_string, else: rest
          raise ArgumentError, "GQL parse error: unexpected input near #{inspect(unexpected)}"
        else
          raise ArgumentError, "GQL parse error: #{inspect(reason)}"
        end
    end
  end

  @doc """
  Executes an `%OpenGQL.Statement{}` against a SQL database.

  ## Parameters

  - `statement` — the `%OpenGQL.Statement{}` returned by the `~GQL` / `~G` sigil
    or `parse_and_build/1`.
  - `query_fn` — a 2-arity function `(sql, params) -> {:ok, result} | {:error, reason}`
    that executes a SQL query.  Pass `&MyRepo.query/2` for Ecto repos.

  ## Return values

  - **SELECT** — `{:ok, [%{column => value}]}`: a list of row maps where the
    keys are the SQL column names (`"key"`, `"value"` for single-node queries;
    `"n1_key"`, `"n1_value"`, `"n2_key"`, `"n2_value"` for path/cross queries).
  - **INSERT** — `{:ok, results}` where `results` is a list of raw results from
    each individual INSERT operation.
  - **UPDATE** / **DELETE** — `{:ok, result}` where `result` is the raw driver
    result from the single (or last) SQL statement executed.
  - `{:error, reason}` if any step fails.

  ## Examples

      # SELECT
      stmt = ~G"MATCH (a:Person) RETURN a"
      {:ok, rows} = OpenGQL.execute(stmt, &MyRepo.query/2)
      Enum.each(rows, fn row -> IO.inspect(row["key"]) end)

      # CREATE
      stmt = ~G[CREATE (a:Person {name: "Alice"})]
      {:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

      # DELETE
      stmt = ~G"MATCH (a:Person) DELETE a"
      {:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

  """
  def execute(%Statement{type: :select, operations: [{sql, params}]}, query_fn)
      when is_function(query_fn, 2) do
    case query_fn.(sql, params) do
      {:ok, result} -> {:ok, rows_to_maps(result)}
      {:error, _} = err -> err
    end
  end

  def execute(%Statement{type: :insert, operations: ops}, query_fn)
      when is_function(query_fn, 2) do
    case Enum.reduce_while(ops, {:ok, []}, fn {sql, params}, {:ok, acc} ->
           case query_fn.(sql, params) do
             {:ok, result} -> {:cont, {:ok, [result | acc]}}
             {:error, _} = err -> {:halt, err}
           end
         end) do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, _} = err -> err
    end
  end

  def execute(%Statement{type: type, operations: [{sql, params}]}, query_fn)
      when type in [:update, :delete] and is_function(query_fn, 2) do
    query_fn.(sql, params)
  end

  def execute(%Statement{type: :delete, operations: ops}, query_fn)
      when is_function(query_fn, 2) do
    Enum.reduce_while(ops, {:ok, nil}, fn {sql, params}, _ ->
      case query_fn.(sql, params) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  # Converts a DB result (from Ecto or any driver that returns %{rows:, columns:})
  # into a list of string-keyed maps.
  defp rows_to_maps(%{rows: rows, columns: columns}) do
    Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
  end

  defp rows_to_maps(_other), do: []
end
