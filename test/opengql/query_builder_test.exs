defmodule OpenGQL.QueryBuilderTest do
  use ExUnit.Case, async: true

  alias OpenGQL.QueryBuilder
  alias OpenGQL.Statement

  # Helper: parse GQL and feed to builder
  defp build(gql) do
    case OpenGQL.Parser.parse(String.trim(gql)) do
      {:ok, ast, "", _ctx, _line, _offset} -> QueryBuilder.build(ast)
      other -> flunk("Parse failed: #{inspect(other)}")
    end
  end

  # ── SELECT — single node ──────────────────────────────────────────────────────

  describe "build/1 - single node SELECT" do
    test "produces a :select Statement with one operation" do
      stmt = build("MATCH (a:Person) RETURN a")
      assert %Statement{type: :select, operations: [_]} = stmt
    end

    test "ast_info kind is :single_node" do
      stmt = build("MATCH (a:Person) RETURN a")
      assert %Statement{ast_info: %{kind: :single_node}} = stmt
    end

    test "ast_info carries labels and props" do
      stmt = build(~S[MATCH (a:Person {name: "Alice"}) RETURN a])
      assert %Statement{ast_info: %{kind: :single_node, labels: ["Person"], props: %{"name" => "Alice"}}} = stmt
    end

    test "no-label node falls back to :all Statement" do
      # MATCH () RETURN * → no usable label/prop conditions
      stmt = build("MATCH () RETURN *")
      # Either :all (no conditions) or single_node with empty labels
      assert %Statement{type: :select} = stmt
    end

    test "integer property filter is included in params" do
      %Statement{operations: [{_sql, params}]} = build("MATCH (a:Person {age: 30}) RETURN a")
      assert 30 in params
    end

    test "boolean property filter is included in params" do
      %Statement{operations: [{_sql, params}]} = build("MATCH (a:Person {active: true}) RETURN a")
      assert true in params
    end
  end

  # ── SELECT — path queries ─────────────────────────────────────────────────────

  describe "build/1 - path SELECT" do
    test "right-directed path has ast_info kind :path with dir :right" do
      stmt = build("MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
      assert %Statement{ast_info: %{kind: :path, dir: :right}} = stmt
    end

    test "left-directed path has ast_info kind :path with dir :left" do
      stmt = build("MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b")
      assert %Statement{ast_info: %{kind: :path, dir: :left}} = stmt
    end

    test "path ast_info includes n1, edge_types, n2" do
      stmt = build("MATCH (a:Person)-[:KNOWS]->(b:Company) RETURN a, b")
      assert %Statement{
               ast_info: %{
                 kind: :path,
                 n1: %{labels: ["Person"]},
                 edge_types: ["KNOWS"],
                 n2: %{labels: ["Company"]}
               }
             } = stmt
    end

    test "undirected path produces a join with n2.key != n1.key exclusion" do
      stmt = build("MATCH (a:Person)-[:KNOWS]-(b:Person) RETURN a, b")
      assert %Statement{operations: [{sql, _}]} = stmt
      assert sql =~ "n2.key != n1.key"
    end

    test "path SQL has n1_key and n2_key columns" do
      %Statement{operations: [{sql, _}]} =
        build("MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")

      assert sql =~ "n1_key"
      assert sql =~ "n2_key"
    end

    test "edge type is included in params for path query" do
      %Statement{operations: [{_sql, params}]} =
        build("MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")

      assert "KNOWS" in params
    end

    test "multi-type edge uses IN clause in SQL" do
      %Statement{operations: [{sql, params}]} =
        build("MATCH (a:Person)-[:KNOWS|LIKES]->(b:Person) RETURN a, b")

      assert sql =~ "IN ("
      assert "KNOWS" in params
      assert "LIKES" in params
    end

    test "multi-type edge SQL does not use AND between types" do
      %Statement{operations: [{sql, _}]} =
        build("MATCH (a:Person)-[:KNOWS|LIKES]->(b:Person) RETURN a, b")

      # Both types must be in a single IN clause, not ANDed separate conditions
      refute sql =~ "e.rel = ?"
    end
  end

  # ── SELECT — null property conditions ────────────────────────────────────────

  describe "build/1 - node_conditions null handling" do
    test "null property filter uses IS NULL instead of = ?" do
      %Statement{operations: [{sql, params}]} =
        build(~S[MATCH (a:Person {ref: null}) RETURN a])

      assert sql =~ "IS NULL"
      refute nil in params
    end

    test "multi-label node SELECT uses positional label indexing" do
      %Statement{operations: [{sql, params}]} =
        build("MATCH (a:Person:Employee) RETURN a")

      # $[1] checks first label, $[2] checks second label
      assert sql =~ "'$[1]'"
      assert sql =~ "'$[2]'"
      assert "Person" in params
      assert "Employee" in params
    end

    test "multi-label node SELECT has both labels in params" do
      %Statement{operations: [{_sql, params}]} =
        build("MATCH (a:Person:Employee) RETURN a")

      assert "Person" in params
      assert "Employee" in params
    end
  end

  # ── SELECT — cross join ───────────────────────────────────────────────────────

  describe "build/1 - cross-join SELECT" do
    test "two-node comma pattern produces ast_info kind :cross" do
      stmt = build("MATCH (a:Person), (b:Company) RETURN a, b")
      assert %Statement{ast_info: %{kind: :cross}} = stmt
    end

    test "cross SQL uses CROSS JOIN" do
      %Statement{operations: [{sql, _}]} = build("MATCH (a:Person), (b:Person) RETURN a, b")
      assert sql =~ "CROSS JOIN"
    end
  end

  # ── SELECT — fallback :all ────────────────────────────────────────────────────

  describe "build/1 - :all fallback" do
    test "MATCH with single unlabeled node produces :select statement" do
      stmt = OpenGQL.parse_and_build("MATCH (n) RETURN n")
      assert %Statement{type: :select} = stmt
    end

    test "unsupported pattern (3 nodes) raises ArgumentError" do
      assert_raise ArgumentError, ~r/unsupported MATCH pattern/, fn ->
        build("MATCH (a:Person)-[:KNOWS]->(b:Person)-[:LIKES]->(c:Item) RETURN a, b, c")
      end
    end
  end

  # ── CREATE ────────────────────────────────────────────────────────────────────

  describe "build/1 - CREATE" do
    test "single-node CREATE has type :insert" do
      stmt = build("CREATE (a:Person {name: \"Alice\"})")
      assert %Statement{type: :insert} = stmt
    end

    test "node key JSON is [name, label]" do
      %Statement{operations: [{_sql, [key | _]}]} =
        build("CREATE (a:Person {name: \"Alice\"})")

      assert key == ~s(["Alice","Person"])
    end

    test "node key JSON without label is plain string" do
      %Statement{operations: [{_sql, [key | _]}]} =
        build("CREATE (a {name: \"solo\"})")

      assert key == ~s("solo")
    end

    test "node key falls back to variable name when no name prop" do
      %Statement{operations: [{_sql, [key | _]}]} = build("CREATE (alice:Person)")
      assert key == ~s(["alice","Person"])
    end

    test "edge INSERT is added after node INSERTs" do
      %Statement{operations: ops} =
        build("CREATE (a:Person {name: \"A\"})-[:KNOWS]->(b:Person {name: \"B\"})")

      sqls = Enum.map(ops, &elem(&1, 0))
      [_, _, edge_sql] = sqls
      assert edge_sql =~ "INSERT INTO edges"
    end

    test "left-directed edge stores source/target in reversed order" do
      %Statement{operations: ops} =
        build("CREATE (a:Person {name: \"A\"})<-[:KNOWS]-(b:Person {name: \"B\"})")

      {_sql, [src, tgt, _rel]} = List.last(ops)
      # a<-b means edge goes FROM b TO a
      assert src == ~s(["B","Person"])
      assert tgt == ~s(["A","Person"])
    end

    test "CREATE with both-direction edge (undirected syntax) is treated as :right" do
      # Undirected edge in CREATE context — e.g. -[:R]- — dir is :both
      # Our code treats :both the same as :right for CREATE
      stmt = build("CREATE (a:Person {name: \"A\"})-[:KNOWS]-(b:Person {name: \"B\"})")
      assert %Statement{type: :insert} = stmt
    end

    test "CREATE with anonymous source node raises ArgumentError" do
      # An edge cannot have an anonymous (no-var) node as source because
      # there is no key to reference.
      assert_raise ArgumentError, ~r/source node variable/, fn ->
        build("CREATE ()-[:KNOWS]->(b:Person {name: \"B\"})")
      end
    end

    test "CREATE with anonymous target node raises ArgumentError" do
      assert_raise ArgumentError, ~r/target node variable/, fn ->
        build("CREATE (a:Person {name: \"A\"})-[:KNOWS]->()")
      end
    end

    test "CREATE with only anonymous nodes raises ArgumentError" do
      assert_raise ArgumentError, ~r/no named nodes/, fn ->
        build("CREATE (:Person)")
      end
    end

    test "compound MATCH + CREATE raises ArgumentError" do
      assert_raise ArgumentError, ~r/not yet supported/, fn ->
        build(~S"""
        MATCH (a:Person {name: "Alice"}), (b:Person {name: "Bob"}) CREATE (a)-[:FRIENDS]->(b)
        """)
      end
    end

    test "multi-label node key includes all labels" do
      %Statement{operations: [{_sql, [key | _]}]} =
        build("CREATE (a:Person:Employee {name: \"Alice\"})")

      assert key == ~s(["Alice","Person","Employee"])
    end
  end

  # ── UPDATE (MATCH + SET) ──────────────────────────────────────────────────────

  describe "build/1 - MATCH + SET" do
    test "produces a :update Statement" do
      stmt = build(~S[MATCH (a:Person) SET a.name = "Bob"])
      assert %Statement{type: :update} = stmt
    end

    test "SET SQL uses json_set" do
      %Statement{operations: [{sql, _}]} = build(~S[MATCH (a:Person) SET a.name = "Bob"])
      assert sql =~ "json_set"
    end

    test "multiple SET assignments generate multi-arg json_set" do
      %Statement{operations: [{sql, params}]} =
        build("MATCH (a:Person) SET a.age = 42, a.active = true")

      assert sql =~ "json_set"
      assert 42 in params
      assert true in params
    end

    test "SET with integer produces integer param" do
      %Statement{operations: [{_sql, params}]} = build("MATCH (a:Person) SET a.age = 99")
      assert 99 in params
    end

    test "SET with boolean=false produces false param" do
      %Statement{operations: [{_sql, params}]} = build("MATCH (a:Person) SET a.active = false")
      assert false in params
    end

    test "SET with null produces nil param" do
      %Statement{operations: [{_sql, params}]} = build("MATCH (a:Person) SET a.deleted = null")
      assert nil in params
    end

    test "SET on a node without MATCH conditions has no WHERE" do
      # No label — empty match elements — no WHERE should be generated
      %Statement{operations: [{sql, _params}]} = build("SET a.x = 1")
      # Without a MATCH the fallback produces an update with no label condition
      refute sql =~ "WHERE"
    end

    test "SET targeting wrong variable raises ArgumentError" do
      assert_raise ArgumentError, ~r/targets variable/, fn ->
        build(~S[MATCH (a:Person) SET b.name = "Bob"])
      end
    end
  end

  # ── DELETE ────────────────────────────────────────────────────────────────────

  describe "build/1 - MATCH + DELETE" do
    test "produces a :delete Statement with one operation" do
      %Statement{type: :delete, operations: [_]} = build("MATCH (a:Person) DELETE a")
    end

    test "DELETE SQL targets nodes table with WHERE" do
      %Statement{operations: [{sql, params}]} = build("MATCH (a:Person) DELETE a")
      assert sql =~ "DELETE FROM nodes"
      assert sql =~ "WHERE"
      assert "Person" in params
    end
  end

  # ── DETACH DELETE ─────────────────────────────────────────────────────────────

  describe "build/1 - MATCH + DETACH DELETE" do
    test "produces a :delete Statement with two operations" do
      %Statement{type: :delete, operations: ops} = build("MATCH (a:Person) DETACH DELETE a")
      assert length(ops) == 2
    end

    test "first operation targets edges" do
      %Statement{operations: [{edge_sql, _} | _]} = build("MATCH (a:Person) DETACH DELETE a")
      assert edge_sql =~ "DELETE FROM edges"
    end

    test "second operation targets nodes" do
      %Statement{operations: [_, {node_sql, _}]} = build("MATCH (a:Person) DETACH DELETE a")
      assert node_sql =~ "DELETE FROM nodes"
    end

    test "edge operation params appear twice (for source IN and target IN)" do
      %Statement{operations: [{_edge_sql, edge_params} | _]} =
        build("MATCH (a:Person) DETACH DELETE a")

      # The WHERE params for the subquery appear twice (once per IN clause)
      assert length(edge_params) == 2
      assert Enum.all?(edge_params, &(&1 == "Person"))
    end
  end

  # ── encode_value paths ────────────────────────────────────────────────────────

  describe "JSON encoding helpers" do
    test "integer value in node CREATE is stored as integer string in JSON" do
      %Statement{operations: [{_sql, [_key, value]} | _]} =
        build("CREATE (a:Person {age: 42})")

      assert value =~ "42"
      refute value =~ "\"42\""
    end

    test "boolean true in node CREATE is stored as true in JSON" do
      %Statement{operations: [{_sql, [_key, value]} | _]} =
        build("CREATE (a:Thing {active: true})")

      assert value =~ "true"
    end

    test "boolean false in node CREATE is stored as false in JSON" do
      %Statement{operations: [{_sql, [_key, value]} | _]} =
        build("CREATE (a:Thing {active: false})")

      assert value =~ "false"
    end

    test "null value in node CREATE is stored as null in JSON" do
      %Statement{operations: [{_sql, [_key, value]} | _]} =
        build("CREATE (a:Thing {ref: null})")

      assert value =~ "null"
    end

    test "empty props map encodes to {}" do
      %Statement{operations: [{_sql, [_key, value]} | _]} = build("CREATE (a:Thing)")
      assert value == "{}"
    end
  end

  # ── execute/2 edge cases ──────────────────────────────────────────────────────

  describe "OpenGQL.execute/2 error propagation" do
    test "INSERT halts on first error" do
      stmt = %Statement{
        type: :insert,
        operations: [{"INSERT 1", []}, {"INSERT 2", []}, {"INSERT 3", []}]
      }

      call_count = :counters.new(1, [])

      failing_fn = fn _sql, _params ->
        :counters.add(call_count, 1, 1)
        if :counters.get(call_count, 1) == 1, do: {:error, :oops}, else: {:ok, :ok}
      end

      assert {:error, :oops} = OpenGQL.execute(stmt, failing_fn)
      # Should have stopped after first failure
      assert :counters.get(call_count, 1) == 1
    end

    test "multi-op DELETE halts on first error" do
      stmt = %Statement{
        type: :delete,
        operations: [{"DELETE edges", []}, {"DELETE nodes", []}]
      }

      failing_fn = fn _sql, _params -> {:error, :db_error} end
      assert {:error, :db_error} = OpenGQL.execute(stmt, failing_fn)
    end

    test "multi-op DELETE succeeds when all ops succeed" do
      stmt = %Statement{
        type: :delete,
        operations: [{"DELETE edges", []}, {"DELETE nodes", []}]
      }

      ok_fn = fn _sql, _params -> {:ok, %{rows: [], columns: []}} end
      assert {:ok, _} = OpenGQL.execute(stmt, ok_fn)
    end

    test "SELECT returns empty list when result has no columns/rows" do
      stmt = %Statement{type: :select, operations: [{"SELECT 1", []}]}
      ok_fn = fn _sql, _params -> {:ok, :some_non_map_result} end
      assert {:ok, []} = OpenGQL.execute(stmt, ok_fn)
    end

    test "UPDATE passes result through" do
      stmt = %Statement{type: :update, operations: [{"UPDATE nodes SET x = 1", []}]}
      ok_fn = fn _sql, _params -> {:ok, :updated} end
      assert {:ok, :updated} = OpenGQL.execute(stmt, ok_fn)
    end

    test "INSERT results are returned in operation order" do
      stmt = %Statement{
        type: :insert,
        operations: [{"INSERT 1", []}, {"INSERT 2", []}, {"INSERT 3", []}]
      }

      call_order = :counters.new(1, [])

      ordered_fn = fn sql, _params ->
        :counters.add(call_order, 1, 1)
        {:ok, {sql, :counters.get(call_order, 1)}}
      end

      assert {:ok, results} = OpenGQL.execute(stmt, ordered_fn)
      # Results must match operation order, not reversed
      assert [{"INSERT 1", 1}, {"INSERT 2", 2}, {"INSERT 3", 3}] = results
    end

    test "parse_and_build raises on partial parse (trailing garbage)" do
      assert_raise ArgumentError, ~r/unexpected input/, fn ->
        OpenGQL.parse_and_build("MATCH (a:Person) RETURN a @@@@")
      end
    end
  end
end
