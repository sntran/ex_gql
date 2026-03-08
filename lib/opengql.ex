defmodule OpenGQL do
  @moduledoc """
  An Elixir library for generating `Ecto.Query` using Open Graph Query Language (GQL).

  Provides the `~G` sigil that takes a GQL string (the MATCH pattern subset of ISO
  GQL) and returns an `Ecto.Query` that can be executed with a Repo.

  ## Data Model

  The library works with the following graph schema:

      CREATE TABLE nodes (
        key   TEXT PRIMARY KEY NOT NULL,  -- JSON: string or [id, type]
        value TEXT                        -- JSON: body/properties
      );

      CREATE TABLE edges (
        source TEXT,
        target TEXT,
        rel    TEXT,   -- relationship type
        value  TEXT    -- JSON: edge properties
      );

  ## Example

      import OpenGQL

      # Match a single node
      query = ~G[MATCH (a:Person {name: "Alice"}) RETURN a]
      Repo.all(query)

      # Match a relationship
      query = ~G[MATCH (a:Person {name: "Alice"})-[:KNOWS]->(b:Person) RETURN a, b]
      Repo.all(query)

  """

  alias OpenGQL.Parser
  alias OpenGQL.QueryBuilder

  @doc ~S"""
  Sigil for creating an `Ecto.Query` from a GQL string.

  ## Examples

      iex> import OpenGQL
      iex> query = ~G"MATCH (a:Person) RETURN a"
      iex> is_struct(query, Ecto.Query)
      true

  """
  defmacro sigil_G(term, _modifiers) do
    quote do
      unquote(term)
      |> OpenGQL.parse_and_build()
    end
  end

  @doc """
  Parses a GQL string and builds the corresponding `Ecto.Query`.
  """
  def parse_and_build(gql_string) when is_binary(gql_string) do
    gql_string = String.trim(gql_string)

    case Parser.parse(gql_string) do
      {:ok, ast, "", _ctx, _line, _offset} ->
        QueryBuilder.build(ast)

      {:ok, _ast, rest, _ctx, _line, _offset} ->
        raise ArgumentError, "GQL parse error: unexpected input near #{inspect(rest)}"

      {:error, reason, _rest, _ctx, _line, _offset} ->
        raise ArgumentError, "GQL parse error: #{inspect(reason)}"
    end
  end
end
