defmodule OpenGQLTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import OpenGQL

  doctest OpenGQL

  describe "~G sigil — MATCH + RETURN" do
    test "returns an OpenGQL.Statement struct" do
      stmt = ~G"MATCH (a:Person) RETURN a"
      assert is_struct(stmt, OpenGQL.Statement)
    end

    test "select statement has type :select" do
      stmt = ~G"MATCH (a:Person) RETURN a"
      assert %OpenGQL.Statement{type: :select} = stmt
    end

    test "select statement has exactly one SQL operation" do
      stmt = ~G"MATCH (a:Person) RETURN a"
      assert %OpenGQL.Statement{operations: [_]} = stmt
    end

    test "select SQL targets the nodes table" do
      %OpenGQL.Statement{operations: [{sql, _params}]} = ~G"MATCH (a:Person) RETURN a"
      assert sql =~ "nodes"
    end

    test "label filter is parameterized in the SELECT SQL" do
      %OpenGQL.Statement{operations: [{sql, params}]} = ~G"MATCH (a:Person) RETURN a"
      assert sql =~ "json_extract"
      assert "Person" in params
    end

    test "string property is parameterized" do
      stmt = ~G[MATCH (a:Person {name: "Alice"}) RETURN a]
      %OpenGQL.Statement{operations: [{sql, params}]} = stmt
      assert sql =~ "json_extract"
      assert "Alice" in params
    end

    test "right-directed edge produces a JOIN" do
      %OpenGQL.Statement{operations: [{sql, _params}]} =
        ~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b"

      assert sql =~ "INNER JOIN edges"
      assert sql =~ "n2_key"
    end

    test "left-directed edge also produces a JOIN" do
      %OpenGQL.Statement{operations: [{sql, _params}]} =
        ~G"MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b"

      assert sql =~ "INNER JOIN edges"
    end

    test "comma-separated patterns produce a CROSS JOIN" do
      %OpenGQL.Statement{operations: [{sql, _params}]} =
        ~G"MATCH (a:Person), (b:Person) RETURN a, b"

      assert sql =~ "CROSS JOIN"
    end

    test "accepts trailing semicolon" do
      stmt = ~G"MATCH (a:Person) RETURN a;"
      assert %OpenGQL.Statement{type: :select} = stmt
    end

    test "accepts multiline query" do
      stmt =
        ~G"""
        MATCH (a:Person {name: "Alice"})
        RETURN a
        """

      assert %OpenGQL.Statement{type: :select} = stmt
    end

    test "raises on invalid GQL" do
      assert_raise ArgumentError, ~r/GQL parse error/, fn ->
        ~G"INVALID QUERY"
      end
    end
  end

  describe "~G sigil — CREATE" do
    test "returns a Statement with type :insert" do
      stmt = ~G[CREATE (a:Person {name: "Alice"})]
      assert %OpenGQL.Statement{type: :insert} = stmt
    end

    test "single-node CREATE has one INSERT operation" do
      %OpenGQL.Statement{operations: ops} = ~G[CREATE (a:Person {name: "Alice"})]
      assert length(ops) == 1
      {sql, _} = hd(ops)
      assert sql =~ "INSERT INTO nodes"
    end

    test "node + edge CREATE has three operations (2 nodes + 1 edge)" do
      stmt = ~G"""
      CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})
      """

      assert %OpenGQL.Statement{type: :insert, operations: ops} = stmt
      assert length(ops) == 3
      sqls = Enum.map(ops, &elem(&1, 0))
      assert Enum.count(sqls, &String.contains?(&1, "nodes")) == 2
      assert Enum.count(sqls, &String.contains?(&1, "edges")) == 1
    end

    test "CREATE builds correct node key JSON" do
      %OpenGQL.Statement{operations: [{_sql, params} | _]} =
        ~G[CREATE (a:Person {name: "Alice"})]

      assert ~s(["Alice","Person"]) in params
    end

    test "CREATE encodes node value as JSON" do
      %OpenGQL.Statement{operations: [{_sql, [_key, value]} | _]} =
        ~G[CREATE (a:Person {name: "Alice"})]

      assert value =~ "Alice"
    end
  end

  describe "~G sigil — SET" do
    test "returns a Statement with type :update" do
      stmt = ~G[MATCH (a:Person) SET a.name = "Bob"]
      assert %OpenGQL.Statement{type: :update} = stmt
    end

    test "UPDATE SQL uses json_set" do
      %OpenGQL.Statement{operations: [{sql, _}]} = ~G[MATCH (a:Person) SET a.name = "Bob"]
      assert sql =~ "json_set"
      assert sql =~ "UPDATE nodes"
    end

    test "new value is parameterized" do
      %OpenGQL.Statement{operations: [{_sql, params}]} = ~G[MATCH (a:Person) SET a.name = "Bob"]
      assert "Bob" in params
    end

    test "WHERE condition is generated from MATCH labels" do
      %OpenGQL.Statement{operations: [{sql, params}]} = ~G[MATCH (a:Person) SET a.name = "Bob"]
      assert sql =~ "WHERE"
      assert "Person" in params
    end
  end

  describe "~G sigil — DELETE" do
    test "returns a Statement with type :delete" do
      stmt = ~G"MATCH (a:Person) DELETE a"
      assert %OpenGQL.Statement{type: :delete} = stmt
    end

    test "DELETE SQL targets the nodes table" do
      %OpenGQL.Statement{operations: [{sql, _}]} = ~G"MATCH (a:Person) DELETE a"
      assert sql =~ "DELETE FROM nodes"
    end

    test "DELETE WHERE condition is parameterized" do
      %OpenGQL.Statement{operations: [{sql, params}]} = ~G"MATCH (a:Person) DELETE a"
      assert sql =~ "WHERE"
      assert "Person" in params
    end

    test "DETACH DELETE returns a :delete Statement with two operations" do
      stmt = ~G"MATCH (a:Person) DETACH DELETE a"
      assert %OpenGQL.Statement{type: :delete, operations: ops} = stmt
      assert length(ops) == 2
      [{edge_sql, _}, {node_sql, _}] = ops
      assert edge_sql =~ "DELETE FROM edges"
      assert node_sql =~ "DELETE FROM nodes"
    end
  end

  describe "property-based tests" do
    property "any valid label name produces a valid :select statement" do
      check all(
              label <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/))
            ) do
        gql = "MATCH (n:#{label}) RETURN n"
        stmt = OpenGQL.parse_and_build(gql)
        assert %OpenGQL.Statement{type: :select} = stmt
        %OpenGQL.Statement{operations: [{_sql, params}]} = stmt
        assert label in params
      end
    end

    property "any valid relationship type produces a :select statement with a JOIN" do
      check all(
              rel_type <-
                string(:alphanumeric)
                |> filter(&(String.length(&1) > 0))
                |> filter(&String.match?(&1, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/))
            ) do
        gql = "MATCH (a:Node)-[:#{rel_type}]->(b:Node) RETURN a, b"
        stmt = OpenGQL.parse_and_build(gql)
        assert %OpenGQL.Statement{type: :select} = stmt
        %OpenGQL.Statement{operations: [{sql, params}]} = stmt
        assert sql =~ "INNER JOIN"
        assert rel_type in params
      end
    end
  end
end
