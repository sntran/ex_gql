defmodule OpenGQL.IntegrationTest do
  use OpenGQL.DataCase, async: false

  describe "MATCH + RETURN (select)" do
    test "matches a node by label" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      results = Repo.all(~G"MATCH (a:Person) RETURN a")
      assert length(results) == 1
      assert hd(results).key == ~s(["alice","Person"])
    end

    test "does not match nodes with a different label" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      results = Repo.all(~G"MATCH (a:Company) RETURN a")
      assert results == []
    end

    test "matches a node by label and string property" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      results = Repo.all(~G[MATCH (a:Person {name: "Alice"}) RETURN a])
      assert length(results) == 1
      node = hd(results)
      assert node.key == ~s(["alice","Person"])
    end

    test "returns all matching nodes when there are multiple" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      results = Repo.all(~G"MATCH (a:Person) RETURN a")
      assert length(results) == 2
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

      results = Repo.all(~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
      assert length(results) == 1
      {a, b} = hd(results)
      assert a.key == ~s(["alice","Person"])
      assert b.key == ~s(["bob","Person"])
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

      results = Repo.all(~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
      assert results == []
    end

    test "matches a left-directed edge" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["bob","Person"]),
          target: ~s(["alice","Person"]),
          rel: "KNOWS"
        })

      # a<-[:KNOWS]-b means edge goes FROM b TO a
      results = Repo.all(~G"MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b")
      assert length(results) == 1
      {a, _b} = hd(results)
      assert a.key == ~s(["alice","Person"])
    end

    test "MATCH with multiple comma-separated patterns" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      results = Repo.all(~G"MATCH (a:Person), (b:Person) RETURN a, b")
      # 2 nodes -> 4 cross-join pairs (including self-joins)
      assert length(results) == 4
    end
  end

  describe "CREATE" do
    test "creates a single node" do
      multi = ~G"CREATE (a:Person {name: \"Alice\"})"
      assert %Ecto.Multi{} = multi
      {:ok, _result} = Repo.transaction(multi)

      nodes = Repo.all(from n in Node, select: n)
      assert length(nodes) == 1
      assert hd(nodes).key == ~s(["Alice","Person"])
    end

    test "creates two nodes with an edge" do
      multi = ~G"""
      CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})
      """

      assert %Ecto.Multi{} = multi
      {:ok, _result} = Repo.transaction(multi)

      nodes = Repo.all(from n in Node, order_by: n.key, select: n)
      assert length(nodes) == 2

      edges = Repo.all(from e in Edge, select: e)
      assert length(edges) == 1
      edge = hd(edges)
      assert edge.rel == "KNOWS"
    end

    test "created edge has correct source and target" do
      multi = ~G"""
      CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})
      """

      {:ok, _} = Repo.transaction(multi)

      [edge] = Repo.all(from e in Edge, select: e)
      assert edge.source == ~s(["Alice","Person"])
      assert edge.target == ~s(["Bob","Person"])
    end
  end

  describe "MATCH + DELETE" do
    test "deletes matched nodes" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["corp","Company"]), value: ~s({"name":"Corp"})})

      {:delete, query} = ~G"MATCH (a:Person) DELETE a"
      Repo.delete_all(query)

      remaining = Repo.all(from n in Node, select: n)
      assert length(remaining) == 1
      assert hd(remaining).key == ~s(["corp","Company"])
    end

    test "DETACH DELETE returns a delete tuple" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:delete, query} = ~G"MATCH (a:Person) DETACH DELETE a"
      assert %Ecto.Query{} = query
      {count, _} = Repo.delete_all(query)
      assert count == 1
    end
  end

  describe "MATCH + SET" do
    test "returns an update tuple with the base query and assignments" do
      result = ~G[MATCH (a:Person) SET a.name = "Bob"]
      assert {:update, %Ecto.Query{}, assignments} = result
      assert [{"a", "name", "Bob"}] = assignments
    end

    test "can apply update_all using the returned query and assignments" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:update, base_query, _assignments} = ~G[MATCH (a:Person) SET a.name = "Bob"]

      # Apply update using Ecto's update_all with a JSON patch on the value column
      Repo.update_all(base_query, set: [value: ~s({"name":"Bob"})])

      [updated] = Repo.all(from n in Node, select: n)
      assert updated.value == ~s({"name":"Bob"})
    end
  end

  describe "Ecto associations" do
    test "Node.outgoing_edges association loads edges from source" do
      {:ok, alice} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, bob} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: alice.key,
          target: bob.key,
          rel: "KNOWS"
        })

      loaded = Repo.preload(alice, :outgoing_edges)
      assert length(loaded.outgoing_edges) == 1
      assert hd(loaded.outgoing_edges).rel == "KNOWS"
    end

    test "Node.incoming_edges association loads edges pointing to target" do
      {:ok, alice} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, bob} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: alice.key,
          target: bob.key,
          rel: "KNOWS"
        })

      loaded = Repo.preload(bob, :incoming_edges)
      assert length(loaded.incoming_edges) == 1
      assert hd(loaded.incoming_edges).source == alice.key
    end

    test "Edge.source_node association loads the source node" do
      {:ok, alice} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:ok, bob} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, edge} =
        Repo.insert(%Edge{
          source: alice.key,
          target: bob.key,
          rel: "KNOWS"
        })

      loaded = Repo.preload(edge, [:source_node, :target_node])
      assert loaded.source_node.key == alice.key
      assert loaded.target_node.key == bob.key
    end
  end
end
