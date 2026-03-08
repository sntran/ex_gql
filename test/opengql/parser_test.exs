defmodule OpenGQL.ParserTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OpenGQL.Parser

  describe "parse/1 - node patterns" do
    test "empty node" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} = Parser.parse("MATCH () RETURN *")
      assert [{:path, [{:node, []}]}] = Keyword.get(clauses, :match)
    end

    test "node with variable" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} = Parser.parse("MATCH (a) RETURN a")
      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      assert Keyword.get(attrs, :var) == ["a"]
    end

    test "node with label" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) RETURN a")

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      assert Keyword.get(attrs, :labels) == ["Person"]
    end

    test "node with multiple labels" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person:Employee) RETURN a")

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      assert Keyword.get(attrs, :labels) == ["Person", "Employee"]
    end

    test "node with string property" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person {name: "Alice"}) RETURN a])

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      props = Keyword.get(attrs, :props)
      assert props != nil
    end

    test "node with integer property" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person {age: 30}) RETURN a")

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      props = Keyword.get(attrs, :props)
      assert props != nil
    end

    test "node with boolean property" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person {active: true}) RETURN a")

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      props = Keyword.get(attrs, :props)
      assert props != nil
    end
  end

  describe "parse/1 - path patterns" do
    test "right-directed edge" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")

      match = Keyword.get(clauses, :match)
      assert [{:path, path_elements}] = match
      assert length(path_elements) == 3
      assert [{:node, _}, {:edge_right, _}, {:node, _}] = path_elements
    end

    test "left-directed edge" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b")

      match = Keyword.get(clauses, :match)
      assert [{:path, path_elements}] = match
      assert [{:node, _}, {:edge_left, _}, {:node, _}] = path_elements
    end

    test "edge with type" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a)-[:KNOWS]->(b) RETURN a, b")

      match = Keyword.get(clauses, :match)
      assert [{:path, [_, {:edge_right, edge_attrs}, _]}] = match
      assert Keyword.get(edge_attrs, :types) == ["KNOWS"]
    end
  end

  describe "parse/1 - MATCH with multiple patterns" do
    test "two comma-separated node patterns" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person), (b:Person) RETURN a, b")

      match = Keyword.get(clauses, :match)
      assert length(match) == 2
    end
  end

  describe "parse/1 - RETURN clause" do
    test "single item" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} = Parser.parse("MATCH (a) RETURN a")
      assert Keyword.get(clauses, :return) == ["a"]
    end

    test "multiple items" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a)-[:R]->(b) RETURN a, b")

      assert Keyword.get(clauses, :return) == ["a", "b"]
    end

    test "wildcard *" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} = Parser.parse("MATCH (a) RETURN *")
      assert Keyword.get(clauses, :return) == ["*"]
    end
  end

  describe "property-based tests" do
    property "any valid GQL identifier is accepted as a variable" do
      check all(
              var <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/))
            ) do
        gql = "MATCH (#{var}:Person) RETURN #{var}"
        assert {:ok, _, "", _, _, _} = Parser.parse(gql)
      end
    end

    property "any valid label produces a parseable node pattern" do
      check all(
              label <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/))
            ) do
        gql = "MATCH (n:#{label}) RETURN n"
        assert {:ok, _, "", _, _, _} = Parser.parse(gql)
      end
    end

    property "any valid relationship type is parsed correctly" do
      check all(
              rel_type <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/))
            ) do
        gql = "MATCH (a:Node)-[:#{rel_type}]->(b:Node) RETURN a, b"
        assert {:ok, [{:statement, clauses}], "", _, _, _} = Parser.parse(gql)
        match = Keyword.get(clauses, :match)
        assert [{:path, [_, {:edge_right, edge_attrs}, _]}] = match
        assert Keyword.get(edge_attrs, :types) == [rel_type]
      end
    end
  end
end
