defmodule OpenGQL.Schema.Edge do
  @moduledoc """
  Ecto schema for graph edges.

  ## Table Structure

      CREATE TABLE edges (
        source TEXT,
        target TEXT,
        rel    TEXT,
        value  TEXT
      );
  """

  use Ecto.Schema

  @primary_key false
  schema "edges" do
    field :source, :string
    field :target, :string
    field :rel, :string
    field :value, :string

    belongs_to :source_node, OpenGQL.Schema.Node,
      foreign_key: :source,
      references: :key,
      type: :string,
      define_field: false

    belongs_to :target_node, OpenGQL.Schema.Node,
      foreign_key: :target,
      references: :key,
      type: :string,
      define_field: false
  end
end
