defmodule OpenGQL.Schema.Edge do
  @moduledoc """
  Ecto schema for graph edges.

  ## Table Structure

      CREATE TABLE edges (
        source TEXT,
        target TEXT,
        rel    TEXT,   -- relationship type
        value  TEXT    -- JSON: edge properties
      );

  """

  use Ecto.Schema

  @primary_key false
  schema "edges" do
    field :source, :string
    field :target, :string
    field :rel, :string
    field :value, :string
  end
end
