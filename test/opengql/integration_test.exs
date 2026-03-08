defmodule OpenGQL.IntegrationTest do
  use OpenGQL.DataCase, async: false

  describe "MATCH + RETURN (select)" do
    test "matches a node by label" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      query = ~G"MATCH (a:Person) RETURN a"
      results = Repo.all(query)
      assert length(results) == 1
    end

    test "matches a node by label and property" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      query = ~G"MATCH (a:Person {name: \"Alice\"}) RETURN a"
      results = Repo.all(query)
      assert length(results) == 1
    end

    test "matches a path with directed edge" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{
          source: ~s(["alice","Person"]),
          target: ~s(["bob","Person"]),
          rel: "KNOWS"
        })

      query = ~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b"
      results = Repo.all(query)
      assert length(results) == 1
    end
  end

  describe "CREATE" do
    test "creates a node" do
      multi = ~G"CREATE (a:Person {name: \"Alice\"})"
      assert %Ecto.Multi{} = multi
      {:ok, result} = Repo.transaction(multi)
      assert map_size(result) >= 1

      nodes = Repo.all(from n in Node, select: n)
      assert length(nodes) == 1
    end

    test "creates nodes and an edge" do
      multi = ~G"CREATE (a:Person {name: \"Alice\"})-[:KNOWS]->(b:Person {name: \"Bob\"})"
      assert %Ecto.Multi{} = multi
      {:ok, _result} = Repo.transaction(multi)

      nodes = Repo.all(from n in Node, select: n)
      assert length(nodes) == 2

      edges = Repo.all(from e in Edge, select: e)
      assert length(edges) == 1
    end
  end

  describe "MATCH + DELETE" do
    test "deletes a matched node" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})

      {:delete, query} = ~G"MATCH (a:Person) DELETE a"
      Repo.delete_all(query)

      nodes = Repo.all(from n in Node, select: n)
      assert nodes == []
    end
  end

  describe "MATCH + SET" do
    test "returns an update tuple" do
      result = ~G"MATCH (a:Person) SET a.name = \"Bob\""
      assert {:update, %Ecto.Query{}, _assignments} = result
    end
  end
end
