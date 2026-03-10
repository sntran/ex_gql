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

  describe "parse/1 - additional query clauses" do
    test "WHERE with comparison condition" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.age >= 21 RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE with OR condition" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.age >= 21 OR a.active = true RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
      assert Enum.any?(where_clause, fn
               {:logical, _} -> true
               _ -> false
             end)
    end

    test "FILTER with string equality" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person) FILTER a.name = "Alice" RETURN a])

      filter_clause = Keyword.get(clauses, :filter)
      assert is_list(filter_clause)
      assert filter_clause != []
    end

    test "ORDER BY with explicit directions" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) RETURN a ORDER BY a.age DESC, a.name ASC")

      order_clause = Keyword.get(clauses, :order_by)
      assert is_list(order_clause)
      assert length(order_clause) == 2
    end

    test "LIMIT parses integer" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) RETURN a LIMIT 10")

      assert Keyword.get(clauses, :limit) == [10]
    end

    test "OFFSET parses integer" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) RETURN a OFFSET 5")

      assert Keyword.get(clauses, :offset) == [5]
    end

    test "SKIP parses integer" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) RETURN a SKIP 3")

      assert Keyword.get(clauses, :skip) == [3]
    end

    test "FINISH parses as terminal clause" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) RETURN a FINISH")

      assert Keyword.has_key?(clauses, :finish)
    end

    test "WHERE supports IS NULL" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.ref IS NULL RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports IS NOT NULL" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.ref IS NOT NULL RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports IS TRUE" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.active IS TRUE RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports IS NOT FALSE" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.active IS NOT FALSE RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports IS FALSE" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.active IS FALSE RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports IN list predicate" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S|MATCH (a:Person) WHERE a.name IN ["Alice", "Bob"] RETURN a|)

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports CONTAINS predicate" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person) WHERE a.name CONTAINS "li" RETURN a])

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports STARTS WITH predicate" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person) WHERE a.name STARTS WITH "Al" RETURN a])

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports ENDS WITH predicate" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person) WHERE a.name ENDS WITH "ce" RETURN a])

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports NOT predicate" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person) WHERE NOT a.active = true RETURN a])

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
      assert Enum.any?(where_clause, fn
               {:unary, _} -> true
               _ -> false
             end)
    end

    test "WHERE supports grouped predicates with parentheses" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(
                 ~S[MATCH (a:Person) WHERE (a.age >= 21 OR a.name = "Bob") AND a.active = true RETURN a]
               )

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
      assert Enum.any?(where_clause, fn
               {:group, _} -> true
               _ -> false
             end)
    end

    test "WHERE supports XOR operator" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S[MATCH (a:Person) WHERE a.active = true XOR a.staff = true RETURN a])

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
      assert Enum.any?(where_clause, fn
               {:logical, [:xor]} -> true
               _ -> false
             end)
    end

    test "WHERE supports nested parenthesized expressions" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(
                 ~S[MATCH (a:Person) WHERE ((a.age >= 21 OR a.name = "Bob") AND (NOT (a.staff = 1 XOR a.active = 1))) RETURN a]
               )

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports unary NOT stacking" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE NOT NOT a.active = 1 RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
      assert Enum.count(where_clause, fn
               {:unary, _} -> true
               _ -> false
             end) >= 1
    end

    test "WHERE supports BETWEEN predicate" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse("MATCH (a:Person) WHERE a.age BETWEEN 18 AND 30 RETURN a")

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
    end

    test "WHERE supports NOT IN predicate" do
      assert {:ok, [{:statement, clauses}], "", _, _, _} =
               Parser.parse(~S|MATCH (a:Person) WHERE a.name NOT IN ["Alice", "Bob"] RETURN a|)

      where_clause = Keyword.get(clauses, :where)
      assert is_list(where_clause)
      assert where_clause != []
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

    property "WHERE clauses with valid identifiers and integer values parse" do
      check all(
              var <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              prop <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              value <- integer(0..10_000)
            ) do
        gql = "MATCH (#{var}:Person) WHERE #{var}.#{prop} = #{value} RETURN #{var}"
        assert {:ok, _, "", _, _, _} = Parser.parse(gql)
      end
    end

    property "LIMIT/OFFSET values parse for non-negative integers" do
      check all(limit <- integer(0..1_000), offset <- integer(0..1_000)) do
        gql = "MATCH (a:Person) RETURN a LIMIT #{limit} OFFSET #{offset}"
        assert {:ok, _, "", _, _, _} = Parser.parse(gql)
      end
    end

    property "OR predicates parse with valid identifiers and integer values" do
      check all(
              var <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              prop1 <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              prop2 <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              v1 <- integer(0..10_000),
              v2 <- integer(0..10_000)
            ) do
        gql =
          "MATCH (#{var}:Person) WHERE #{var}.#{prop1} = #{v1} OR #{var}.#{prop2} = #{v2} RETURN #{var}"

        assert {:ok, _, "", _, _, _} = Parser.parse(gql)
      end
    end

    property "grouped boolean predicates parse with valid identifiers" do
      check all(
              var <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              p1 <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              p2 <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              p3 <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              v1 <- integer(0..1_000),
              v2 <- integer(0..1_000),
              v3 <- integer(0..1_000)
            ) do
        gql =
          "MATCH (#{var}:Person) WHERE (#{var}.#{p1} = #{v1} OR #{var}.#{p2} = #{v2}) AND NOT #{var}.#{p3} = #{v3} RETURN #{var}"

        assert {:ok, _, "", _, _, _} = Parser.parse(gql)
      end
    end

    property "BETWEEN predicates parse with generated integer bounds" do
      check all(
              var <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              prop <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)),
              low <- integer(0..100),
              high <- integer(101..200)
            ) do
        gql = "MATCH (#{var}:Person) WHERE #{var}.#{prop} BETWEEN #{low} AND #{high} RETURN #{var}"
        assert {:ok, _, "", _, _, _} = Parser.parse(gql)
      end
    end
  end
end
