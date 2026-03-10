defmodule OpenGQL.Test.Node do
  @moduledoc """
  Ecto schema for graph nodes — used in tests only.

  ## Table Structure

      CREATE TABLE nodes (
        key   TEXT PRIMARY KEY NOT NULL,
        value TEXT
      );
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "nodes" do
    field :value, :string
    has_many :outgoing_edges, OpenGQL.Test.Edge, foreign_key: :source, references: :key
    has_many :incoming_edges, OpenGQL.Test.Edge, foreign_key: :target, references: :key
  end
end
