defmodule OpenGQL.QueryableBranchTest do
  use OpenGQL.DataCase, async: false

  alias OpenGQL.Statement

  describe "Ecto.Queryable branch coverage" do
    test "all-nodes query returns every node for kind :all" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      stmt = %Statement{type: :select, operations: [{"", []}], ast_info: %{kind: :all}}

      rows = Repo.all(stmt)

      assert Enum.map(rows, & &1["key"]) |> Enum.sort() ==
               [~s(["alice","Person"]), ~s(["bob","Person"])]
    end

    test "single_node query handles nil and non-nil property predicates" do
      {:ok, _} =
        Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice","ref":null})})

      {:ok, _} =
        Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob","ref":"x"})})

      stmt_nil = %Statement{
        type: :select,
        operations: [{"", []}],
        ast_info: %{kind: :single_node, labels: ["Person"], props: %{"ref" => nil}}
      }

      stmt_non_nil = %Statement{
        type: :select,
        operations: [{"", []}],
        ast_info: %{kind: :single_node, labels: ["Person"], props: %{"name" => "Bob"}}
      }

      nil_rows = Repo.all(stmt_nil)
      non_nil_rows = Repo.all(stmt_non_nil)

      assert Enum.map(nil_rows, & &1["key"]) == [~s(["alice","Person"])]
      assert Enum.map(non_nil_rows, & &1["key"]) == [~s(["bob","Person"])]
    end

    test "path query with unknown dir falls back to undirected join branch" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{source: ~s(["alice","Person"]), target: ~s(["bob","Person"]), rel: "KNOWS"})

      stmt = %Statement{
        type: :select,
        operations: [{"", []}],
        ast_info: %{
          kind: :path,
          dir: :unknown,
          n1: %{labels: ["Person"], props: %{}},
          edge_types: ["KNOWS"],
          n2: %{labels: ["Person"], props: %{}}
        }
      }

      rows = Repo.all(stmt)
      assert length(rows) >= 1
      assert Enum.all?(rows, &Map.has_key?(&1, "n1_key"))
      assert Enum.all?(rows, &Map.has_key?(&1, "n2_key"))
    end

    test "path query with empty edge_types keeps all edge rel values" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      {:ok, _} =
        Repo.insert(%Edge{source: ~s(["alice","Person"]), target: ~s(["bob","Person"]), rel: "FRIEND"})

      stmt = %Statement{
        type: :select,
        operations: [{"", []}],
        ast_info: %{
          kind: :path,
          dir: :right,
          n1: %{labels: ["Person"], props: %{}},
          edge_types: [],
          n2: %{labels: ["Person"], props: %{}}
        }
      }

      rows = Repo.all(stmt)
      assert length(rows) == 1
      assert hd(rows)["n1_key"] == ~s(["alice","Person"])
      assert hd(rows)["n2_key"] == ~s(["bob","Person"])
    end

    test "cross query applies n1 and n2 non-nil property predicates" do
      {:ok, _} = Repo.insert(%Node{key: ~s(["alice","Person"]), value: ~s({"name":"Alice"})})
      {:ok, _} = Repo.insert(%Node{key: ~s(["bob","Person"]), value: ~s({"name":"Bob"})})

      stmt = %Statement{
        type: :select,
        operations: [{"", []}],
        ast_info: %{
          kind: :cross,
          n1: %{labels: ["Person"], props: %{"name" => "Alice"}},
          n2: %{labels: ["Person"], props: %{"name" => "Bob"}}
        }
      }

      rows = Repo.all(stmt)
      assert length(rows) == 1
      assert hd(rows)["n1_key"] == ~s(["alice","Person"])
      assert hd(rows)["n2_key"] == ~s(["bob","Person"])
    end
  end
end
