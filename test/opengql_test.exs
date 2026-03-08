defmodule OpenGQLTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import OpenGQL

  doctest OpenGQL

  describe "~G sigil" do
    test "returns an Ecto.Query struct" do
      query = ~G"MATCH (a:Person) RETURN a"
      assert is_struct(query, Ecto.Query)
    end

    test "single node with label" do
      query = ~G"MATCH (a:Person) RETURN a"
      assert %Ecto.Query{} = query
      assert inspect(query) =~ "Node"
    end

    test "single node with label and string property" do
      query = ~G[MATCH (a:Person {name: "Alice"}) RETURN a]
      assert %Ecto.Query{} = query
    end

    test "two-node pattern with directed right edge" do
      query = ~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b"
      assert %Ecto.Query{} = query
    end

    test "two-node pattern with directed left edge" do
      query = ~G"MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b"
      assert %Ecto.Query{} = query
    end

    test "accepts trailing semicolon" do
      query = ~G"MATCH (a:Person) RETURN a;"
      assert %Ecto.Query{} = query
    end

    test "accepts multiline query" do
      query =
        ~G"""
        MATCH (a:Person {name: "Alice"})
        RETURN a
        """

      assert %Ecto.Query{} = query
    end

    test "raises on invalid GQL" do
      assert_raise ArgumentError, ~r/GQL parse error/, fn ->
        ~G"INVALID QUERY"
      end
    end
  end

  describe "property-based tests" do
    property "any valid label name produces a valid query" do
      check all(
              label <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/))
            ) do
        gql = "MATCH (n:#{label}) RETURN n"
        query = OpenGQL.parse_and_build(gql)
        assert %Ecto.Query{} = query
      end
    end

    property "any valid relationship type produces a valid query" do
      check all(
              rel_type <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/))
            ) do
        gql = "MATCH (a:Node)-[:#{rel_type}]->(b:Node) RETURN a, b"
        query = OpenGQL.parse_and_build(gql)
        assert %Ecto.Query{} = query
      end
    end
  end
end
