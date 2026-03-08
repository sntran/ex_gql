defmodule OpenGQL.Schema.Node do
  @moduledoc """
  Ecto schema for graph nodes.

  ## Table Structure

      CREATE TABLE nodes (
        key   TEXT PRIMARY KEY NOT NULL,  -- JSON: string or [id, type]
        value TEXT                        -- JSON: body/properties
      );

  The `key` field is a JSON value — either a plain string ID (`"alice"`) or a
  `[id, type]` array (`["alice", "Person"]`).

  The `value` field holds the node's properties as a JSON object.
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "nodes" do
    field :value, :string
  end
end
