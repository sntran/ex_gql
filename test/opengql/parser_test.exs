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

    test "node with boolean=false property" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person {active: false}) RETURN a")

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      props = Keyword.get(attrs, :props)
      # props is a tagged list like [:props, "active", {:boolean, false}]
      assert props != nil
      assert {:boolean, false} in props
    end

    test "node with null property" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person {ref: null}) RETURN a")

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      props = Keyword.get(attrs, :props)
      assert props != nil
      assert {:null, nil} in props
    end

    test "node with multiple properties" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person {name: "Alice", age: 30}) RETURN a])

      match = Keyword.get(clauses, :match)
      assert [{:path, [{:node, attrs}]}] = match
      props = Keyword.get(attrs, :props)
      assert props != nil
    end

    test "node with negative integer property" do
      assert {:ok, _, "", _, _, _} = Parser.parse("MATCH (a:Data {temp: -5}) RETURN a")
    end

    test "node with positive-sign integer property" do
      assert {:ok, _, "", _, _, _} = Parser.parse("MATCH (a:Data {temp: +5}) RETURN a")
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

    test "undirected edge" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person)-[:KNOWS]-(b:Person) RETURN a, b")

      match = Keyword.get(clauses, :match)
      assert [{:path, path_elements}] = match
      assert [{:node, _}, {:edge_undirected, _}, {:node, _}] = path_elements
    end

    test "edge with type" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a)-[:KNOWS]->(b) RETURN a, b")

      match = Keyword.get(clauses, :match)
      assert [{:path, [_, {:edge_right, edge_attrs}, _]}] = match
      assert Keyword.get(edge_attrs, :types) == ["KNOWS"]
    end

    test "edge without type (typeless)" do
      assert {:ok, _, "", _, _, _} = Parser.parse("MATCH (a)-[]->(b) RETURN a, b")
    end

    test "edge with multiple types (pipe-separated)" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a)-[:KNOWS|LIKES]->(b) RETURN a, b")

      match = Keyword.get(clauses, :match)
      assert [{:path, [_, {:edge_right, edge_attrs}, _]}] = match
      assert Keyword.get(edge_attrs, :types) == ["KNOWS", "LIKES"]
    end

    test "chained path (three nodes)" do
      assert {:ok, _, "", _, _, _} =
               Parser.parse("MATCH (a:Person)-[:KNOWS]->(b:Person)-[:LIKES]->(c:Item) RETURN a, b, c")
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

  describe "parse/1 - CREATE clause" do
    test "create a single node" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[CREATE (a:Person {name: "Alice"})])

      create = Keyword.get(clauses, :create)
      assert [{:path, [{:node, attrs}]}] = create
      assert Keyword.get(attrs, :labels) == ["Person"]
    end

    test "create two nodes with an edge" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(
                 "CREATE (a:Person {name: \"Alice\"})-[:KNOWS]->(b:Person {name: \"Bob\"})"
               )

      create = Keyword.get(clauses, :create)
      assert [{:path, path_elements}] = create
      assert [{:node, _}, {:edge_right, edge_attrs}, {:node, _}] = path_elements
      assert Keyword.get(edge_attrs, :types) == ["KNOWS"]
    end

    test "MATCH then CREATE" do
      gql =
        ~S[MATCH (a:Person {name: "Alice"})] <>
          ~S[, (b:Person {name: "Bob"})] <>
          " CREATE (a)-[:FRIENDS_WITH]->(b) RETURN a, b"

      assert {:ok, [{:statement, clauses}], "", _, _, _} = Parser.parse(gql)

      assert Keyword.get(clauses, :match) != nil
      assert Keyword.get(clauses, :create) != nil
      assert Keyword.get(clauses, :return) == ["a", "b"]
    end
  end

  describe "parse/1 - SET clause" do
    test "single assignment" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person) SET a.name = "Bob" RETURN a])

      set = Keyword.get(clauses, :set)
      assert [{:assignment, ["a", "name", {:string, "Bob"}]}] = set
    end

    test "multiple assignments" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) SET a.age = 30, a.active = true RETURN a")

      set = Keyword.get(clauses, :set)
      assert length(set) == 2
      assert {:assignment, ["a", "age", {:integer, 30}]} = Enum.at(set, 0)
      assert {:assignment, ["a", "active", {:boolean, true}]} = Enum.at(set, 1)
    end

    test "integer assignment" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) SET a.age = 42 RETURN a")

      set = Keyword.get(clauses, :set)
      assert [{:assignment, ["a", "age", {:integer, 42}]}] = set
    end

    test "null assignment" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) SET a.ref = null RETURN a")

      set = Keyword.get(clauses, :set)
      assert [{:assignment, ["a", "ref", {:null, nil}]}] = set
    end

    test "boolean false assignment" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) SET a.active = false RETURN a")

      set = Keyword.get(clauses, :set)
      assert [{:assignment, ["a", "active", {:boolean, false}]}] = set
    end
  end

  describe "parse/1 - DELETE clause" do
    test "plain DELETE" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) DELETE a")

      delete = Keyword.get(clauses, :delete)
      assert [{:vars, ["a"]}] = delete
    end

    test "DETACH DELETE" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) DETACH DELETE a")

      detach = Keyword.get(clauses, :detach_delete)
      assert [{:vars, ["a"]}] = detach
    end

    test "DELETE multiple variables" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person)-[:KNOWS]->(b:Person) DELETE a, b")

      delete = Keyword.get(clauses, :delete)
      assert [{:vars, ["a", "b"]}] = delete
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
