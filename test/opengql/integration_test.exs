defmodule OpenGQL.IntegrationTest do
  use OpenGQL.DataCase, async: false
  use ExUnitProperties

  # Helper: run a GQL statement against the test SQLite repo.
  defp run(stmt), do: OpenGQL.execute(stmt, &Repo.query/2)

  # Generator for valid GQL identifier characters (letters + digits, starts with letter)
  defp valid_name_gen do
    gen all(
          first <- StreamData.string([?a..?z, ?A..?Z], length: 1),
          rest <- StreamData.string([?a..?z, ?A..?Z, ?0..?9], min_length: 1, max_length: 12)
        ) do
      first <> rest
    end
  end

  # ── MATCH + RETURN ──────────────────────────────────────────────────────────

  describe "MATCH + RETURN (select)" do
    test "matches a node by label" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      stmt = ~G"MATCH (a:Person) RETURN a"
      assert %OpenGQL.Statement{type: :select} = stmt

      {:ok, rows} = run(stmt)
      assert length(rows) == 1
      assert hd(rows)["key"] == ~s(["alice","Person"])
    end

    test "does not match nodes with a different label" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, rows} = run(~G"MATCH (a:Company) RETURN a")
      assert rows == []
    end

    test "matches a node by label and string property" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, rows} = run(~G[MATCH (a:Person {name: "Alice"}) RETURN a])
      assert length(rows) == 1
      assert hd(rows)["key"] == ~s(["alice","Person"])
    end

    test "returns all matching nodes when there are multiple" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, rows} = run(~G"MATCH (a:Person) RETURN a")
      assert length(rows) == 2
    end

    test "matches a path with a directed right edge" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["alice","Person"]),
          target: ~s(["bob","Person"]),
          rel: "KNOWS"
        })

      {:ok, rows} = run(~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
      assert length(rows) == 1
      row = hd(rows)
      assert row["n1_key"] == ~s(["alice","Person"])
      assert row["n2_key"] == ~s(["bob","Person"])
    end

    test "does not match a path with a different edge type" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["alice","Person"]),
          target: ~s(["bob","Person"]),
          rel: "DISLIKES"
        })

      {:ok, rows} = run(~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
      assert rows == []
    end

    test "matches a left-directed edge" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      # edge goes FROM bob TO alice
      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["bob","Person"]),
          target: ~s(["alice","Person"]),
          rel: "KNOWS"
        })

      # a<-[:KNOWS]-b  ⟹  n1 = alice (receives the edge), n2 = bob (sends it)
      {:ok, rows} = run(~G"MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b")
      assert length(rows) == 1
      assert hd(rows)["n1_key"] == ~s(["alice","Person"])
    end

    test "MATCH with multiple comma-separated patterns (cross join)" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, rows} = run(~G"MATCH (a:Person), (b:Person) RETURN a, b")
      # 2 nodes × 2 nodes = 4 rows (including self-pairs)
      assert length(rows) == 4
      # Each row has both n1_key and n2_key
      Enum.each(rows, fn row ->
        assert Map.has_key?(row, "n1_key")
        assert Map.has_key?(row, "n2_key")
      end)
    end

    test "integer property filter is applied correctly" do
      {:ok, _} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice","age":30})})

      {:ok, _} =
        Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob","age":25})})

      {:ok, rows} = run(~G"MATCH (a:Person {age: 30}) RETURN a")
      assert length(rows) == 1
      assert hd(rows)["key"] == ~s(["alice","Person"])
    end
  end

  # ── CREATE ──────────────────────────────────────────────────────────────────

  describe "CREATE" do
    test "creates a single node" do
      stmt = ~G[CREATE (a:Person {name: "Alice"})]
      assert %OpenGQL.Statement{type: :insert} = stmt

      {:ok, _} = run(stmt)

      nodes = Repo.all(from n in Node, select: n)
      assert length(nodes) == 1
      assert hd(nodes).key == ~s(["Alice","Person"])
    end

    test "creates a node with the correct value JSON" do
      {:ok, _} = run(~G[CREATE (a:Person {name: "Alice"})])

      [node] = Repo.all(from n in Node, select: n)
      assert node.value =~ "Alice"
    end

    test "creates two nodes with an edge" do
      stmt = ~G"""
      CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})
      """

      {:ok, results} = run(stmt)
      # One result per INSERT operation (2 nodes + 1 edge)
      assert length(results) == 3

      nodes = Repo.all(from n in Node, order_by: n.key, select: n)
      assert length(nodes) == 2

      edges = Repo.all(from e in Edge, select: e)
      assert length(edges) == 1
      assert hd(edges).rel == "KNOWS"
    end

    test "created edge has correct source and target" do
      {:ok, _} =
        run(~G"""
        CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})
        """)

      [edge] = Repo.all(from e in Edge, select: e)
      assert edge.source == ~s(["Alice","Person"])
      assert edge.target == ~s(["Bob","Person"])
    end

    test "left-directed edge stores source/target in the correct order" do
      {:ok, _} =
        run(~G"""
        CREATE (a:Person {name: "Alice"})<-[:KNOWS]-(b:Person {name: "Bob"})
        """)

      [edge] = Repo.all(from e in Edge, select: e)
      # a<-b means edge FROM b TO a, so source=Bob, target=Alice
      assert edge.source == ~s(["Bob","Person"])
      assert edge.target == ~s(["Alice","Person"])
    end
  end

  # ── MATCH + DELETE ───────────────────────────────────────────────────────────

  describe "MATCH + DELETE" do
    test "deletes matched nodes" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["corp","Company"]), value: ~s({"name":"Corp"})})

      stmt = ~G"MATCH (a:Person) DELETE a"
      assert %OpenGQL.Statement{type: :delete} = stmt

      {:ok, _} = run(stmt)

      remaining = Repo.all(from n in Node, select: n)
      assert length(remaining) == 1
      assert hd(remaining).key == ~s(["corp","Company"])
    end

    test "delete with no matching nodes leaves data intact" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, _} = run(~G"MATCH (a:Robot) DELETE a")

      nodes = Repo.all(from n in Node, select: n)
      assert length(nodes) == 1
    end
  end

  # ── MATCH + DETACH DELETE ────────────────────────────────────────────────────

  describe "MATCH + DETACH DELETE" do
    test "deletes the node and its edges" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["alice","Person"]),
          target: ~s(["bob","Person"]),
          rel: "KNOWS"
        })

      stmt = ~G"MATCH (a:Person) DETACH DELETE a"
      assert %OpenGQL.Statement{type: :delete, operations: ops} = stmt
      assert length(ops) == 2

      {:ok, _} = run(stmt)

      assert Repo.all(from n in Node, select: n) == []
      assert Repo.all(from e in Edge, select: e) == []
    end
  end

  # ── MATCH + SET ──────────────────────────────────────────────────────────────

  describe "MATCH + SET" do
    test "updates a property on matching nodes" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      stmt = ~G[MATCH (a:Person) SET a.name = "Alicia"]
      assert %OpenGQL.Statement{type: :update} = stmt

      {:ok, _} = run(stmt)

      [node] = Repo.all(from n in Node, select: n)
      assert node.value =~ "Alicia"
    end

    test "SET uses json_set so other properties are preserved" do
      {:ok, _} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice","age":30})})

      {:ok, _} = run(~G[MATCH (a:Person) SET a.name = "Alicia"])

      [node] = Repo.all(from n in Node, select: n)
      # age should still be present
      assert node.value =~ "30"
      assert node.value =~ "Alicia"
    end

    test "SET with integer value" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, _} = run(~G"MATCH (a:Person) SET a.age = 42")

      [node] = Repo.all(from n in Node, select: n)
      assert node.value =~ "42"
    end

    test "SET only updates nodes matching the MATCH predicate" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["corp","Company"]), value: ~s({"name":"Corp"})})

      {:ok, _} = run(~G[MATCH (a:Person) SET a.active = true])

      person = Repo.get(Node, ~s(["alice","Person"]))
      company = Repo.get(Node, ~s(["corp","Company"]))
      assert person.value =~ "true"
      refute company.value =~ "true"
    end
  end

  # ── Ecto associations ────────────────────────────────────────────────────────

  describe "Ecto associations (test-support schemas)" do
    test "Node.outgoing_edges loads edges from the source node" do
      {:ok, alice} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, bob} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{source: alice.key, target: bob.key, rel: "KNOWS"})

      loaded = Repo.preload(alice, :outgoing_edges)
      assert length(loaded.outgoing_edges) == 1
      assert hd(loaded.outgoing_edges).rel == "KNOWS"
    end

    test "Node.incoming_edges loads edges pointing to the node" do
      {:ok, alice} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, bob} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} = Repo.insert(%Edge{source: alice.key, target: bob.key, rel: "KNOWS"})

      loaded = Repo.preload(bob, :incoming_edges)
      assert length(loaded.incoming_edges) == 1
      assert hd(loaded.incoming_edges).source == alice.key
    end

    test "Edge.source_node and target_node associations load the correct nodes" do
      {:ok, alice} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, bob} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, edge} = Repo.insert(%Edge{source: alice.key, target: bob.key, rel: "KNOWS"})

      loaded = Repo.preload(edge, [:source_node, :target_node])
      assert loaded.source_node.key == alice.key
      assert loaded.target_node.key == bob.key
    end
  end

  # ── execute/2 function ───────────────────────────────────────────────────────

  describe "OpenGQL.execute/2" do
    test "returns {:error, reason} when query_fn returns an error" do
      stmt = ~G"MATCH (a:Person) RETURN a"

      failing_fn = fn _sql, _params -> {:error, "connection refused"} end

      assert {:error, "connection refused"} = OpenGQL.execute(stmt, failing_fn)
    end

    test "accepts any 2-arity function as the adapter" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      # Use an anonymous function wrapping the Repo
      adapter_fn = fn sql, params -> Repo.query(sql, params) end
      {:ok, rows} = OpenGQL.execute(~G"MATCH (a:Person) RETURN a", adapter_fn)
      assert length(rows) == 1
    end

    test "SELECT result maps have string keys" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, [row]} = run(~G"MATCH (a:Person) RETURN a")
      assert Map.has_key?(row, "key")
      assert Map.has_key?(row, "value")
    end

    test "path SELECT result maps have n1_key, n2_key columns" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["alice","Person"]),
          target: ~s(["bob","Person"]),
          rel: "KNOWS"
        })

      {:ok, [row]} = run(~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
      assert Map.has_key?(row, "n1_key")
      assert Map.has_key?(row, "n1_value")
      assert Map.has_key?(row, "n2_key")
      assert Map.has_key?(row, "n2_value")
    end

    test "INSERT returns a list of per-operation results" do
      {:ok, results} =
        run(~G"""
        CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})
        """)

      assert is_list(results)
      assert length(results) == 3
    end
  end

  # ── Repo.all with ~G sigil (Ecto.Queryable) ───────────────────────────────────

  describe "Repo.all with MATCH statements (Ecto.Queryable)" do
    test "Repo.all accepts a SELECT Statement directly" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      stmt = ~G"MATCH (a:Person) RETURN a"
      results = Repo.all(stmt)
      assert is_list(results)
      assert length(results) == 1
    end

    test "Repo.all returns string-keyed row maps for single-node queries" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      [row] = Repo.all(~G"MATCH (a:Person) RETURN a")
      assert Map.has_key?(row, "key")
      assert Map.has_key?(row, "value")
      assert row["key"] == ~s(["alice","Person"])
    end

    test "Repo.all result matches execute/2 result for single-node query" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      stmt = ~G"MATCH (a:Person) RETURN a"
      {:ok, execute_rows} = run(stmt)
      repo_rows = Repo.all(stmt)

      assert length(repo_rows) == length(execute_rows)

      execute_keys = execute_rows |> Enum.map(& &1["key"]) |> Enum.sort()
      repo_keys = repo_rows |> Enum.map(& &1["key"]) |> Enum.sort()
      assert execute_keys == repo_keys
    end

    test "Repo.all with label filter returns only matching nodes" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["corp","Company"]), value: ~s({"name":"Corp"})})

      results = Repo.all(~G"MATCH (a:Person) RETURN a")
      assert length(results) == 1
      assert hd(results)["key"] == ~s(["alice","Person"])
    end

    test "Repo.all with property filter returns only matching nodes" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      results = Repo.all(~G[MATCH (a:Person {name: "Alice"}) RETURN a])
      assert length(results) == 1
      assert hd(results)["key"] == ~s(["alice","Person"])
    end

    test "Repo.all returns empty list when no nodes match" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      results = Repo.all(~G"MATCH (a:Robot) RETURN a")
      assert results == []
    end

    test "Repo.all with path query returns n1_key/n2_key row maps" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["alice","Person"]),
          target: ~s(["bob","Person"]),
          rel: "KNOWS"
        })

      [row] = Repo.all(~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
      assert row["n1_key"] == ~s(["alice","Person"])
      assert row["n2_key"] == ~s(["bob","Person"])
      assert Map.has_key?(row, "n1_value")
      assert Map.has_key?(row, "n2_value")
    end

    test "Repo.all path result matches execute/2 result" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["alice","Person"]),
          target: ~s(["bob","Person"]),
          rel: "KNOWS"
        })

      stmt = ~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b"
      {:ok, execute_rows} = run(stmt)
      repo_rows = Repo.all(stmt)

      assert length(repo_rows) == length(execute_rows)

      execute_pairs = execute_rows |> Enum.map(&{&1["n1_key"], &1["n2_key"]}) |> Enum.sort()
      repo_pairs = repo_rows |> Enum.map(&{&1["n1_key"], &1["n2_key"]}) |> Enum.sort()
      assert execute_pairs == repo_pairs
    end

    test "Repo.all with cross-join returns n1_key/n2_key row maps" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      rows = Repo.all(~G"MATCH (a:Person), (b:Person) RETURN a, b")
      # 2 nodes × 2 = 4 cross-join pairs
      assert length(rows) == 4
      Enum.each(rows, fn row ->
        assert Map.has_key?(row, "n1_key")
        assert Map.has_key?(row, "n2_key")
      end)
    end

    test "cross-join Repo.all result matches execute/2 result" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      stmt = ~G"MATCH (a:Person), (b:Person) RETURN a, b"
      {:ok, execute_rows} = run(stmt)
      repo_rows = Repo.all(stmt)

      assert length(repo_rows) == length(execute_rows)
    end

    test "Repo.all raises for non-SELECT statements" do
      stmt = ~G"MATCH (a:Person) DELETE a"

      assert_raise ArgumentError, ~r/only.*SELECT/, fn ->
        Repo.all(stmt)
      end
    end
  end

  # ── Property-based data consistency tests ─────────────────────────────────────

  describe "data consistency (property-based)" do
    # Runs the given function inside a transaction that is always rolled back,
    # giving each property-test iteration a clean, isolated DB state without
    # accumulating data between runs.
    defp with_clean_db(fun) do
      {:error, :rolled_back} =
        Repo.transaction(fn ->
          fun.()
          # Always roll back so the next check iteration starts with a clean DB.
          Repo.rollback(:rolled_back)
        end)

      :ok
    end

    property "data created via execute/2 CREATE is retrievable via Repo.all MATCH" do
      check all(name <- valid_name_gen(), max_runs: 20) do
        with_clean_db(fn ->
          create_stmt =
            OpenGQL.parse_and_build("CREATE (a:Person {name: \"#{name}\"})")

          {:ok, _} = OpenGQL.execute(create_stmt, &Repo.query/2)

          match_stmt =
            OpenGQL.parse_and_build("MATCH (a:Person {name: \"#{name}\"}) RETURN a")

          results = Repo.all(match_stmt)

          assert length(results) == 1
          row = hd(results)
          assert row["key"] == "[\"#{name}\",\"Person\"]"
          assert row["value"] =~ name
        end)
      end
    end

    property "Repo.all and execute/2 return identical results for any label" do
      check all(
              label <-
                StreamData.string([?A..?Z], length: 1)
                |> StreamData.bind(fn first ->
                  StreamData.string([?a..?z, ?A..?Z, ?0..?9], min_length: 1, max_length: 8)
                  |> StreamData.map(&(first <> &1))
                end),
              max_runs: 20
            ) do
        with_clean_db(fn ->
          key = "[\"test\",\"#{label}\"]"
          {:ok, _} = Repo.insert(%Node{key: key, value: ~s({"name":"test"})})

          stmt = OpenGQL.parse_and_build("MATCH (a:#{label}) RETURN a")

          {:ok, execute_rows} = OpenGQL.execute(stmt, &Repo.query/2)
          repo_rows = Repo.all(stmt)

          assert length(repo_rows) == length(execute_rows)

          execute_keys = execute_rows |> Enum.map(& &1["key"]) |> Enum.sort()
          repo_keys = repo_rows |> Enum.map(& &1["key"]) |> Enum.sort()
          assert execute_keys == repo_keys
        end)
      end
    end

    property "creating N nodes via execute/2 means Repo.all returns N rows" do
      check all(
              names <-
                StreamData.list_of(valid_name_gen(), min_length: 1, max_length: 5)
                |> StreamData.map(&Enum.uniq/1)
                |> StreamData.filter(&(length(&1) >= 1)),
              max_runs: 15
            ) do
        with_clean_db(fn ->
          Enum.each(names, fn name ->
            create_stmt = OpenGQL.parse_and_build("CREATE (a:Person {name: \"#{name}\"})")
            {:ok, _} = OpenGQL.execute(create_stmt, &Repo.query/2)
          end)

          results = Repo.all(~G"MATCH (a:Person) RETURN a")
          assert length(results) == length(names)
        end)
      end
    end

    property "edge created via execute/2 is retrievable via Repo.all path query" do
      check all(
              src_name <- valid_name_gen(),
              tgt_name <- valid_name_gen(),
              src_name != tgt_name,
              max_runs: 15
            ) do
        with_clean_db(fn ->
          create_stmt =
            OpenGQL.parse_and_build(
              "CREATE (a:Person {name: \"#{src_name}\"})-[:KNOWS]->(b:Person {name: \"#{tgt_name}\"})"
            )

          {:ok, _} = OpenGQL.execute(create_stmt, &Repo.query/2)

          path_stmt =
            OpenGQL.parse_and_build(
              "MATCH (a:Person {name: \"#{src_name}\"})-[:KNOWS]->(b:Person {name: \"#{tgt_name}\"}) RETURN a, b"
            )

          results = Repo.all(path_stmt)
          assert length(results) == 1
          row = hd(results)
          assert row["n1_key"] == "[\"#{src_name}\",\"Person\"]"
          assert row["n2_key"] == "[\"#{tgt_name}\",\"Person\"]"
        end)
      end
    end
  end
end
