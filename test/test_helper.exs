ExUnit.start()

# Start the test repo with in-memory SQLite
{:ok, _} = OpenGQL.Test.Repo.start_link(database: ":memory:", pool_size: 1)

# Create tables
OpenGQL.Test.Repo
|> Ecto.Adapters.SQL.query!(
  "CREATE TABLE IF NOT EXISTS nodes (key TEXT PRIMARY KEY NOT NULL, value TEXT)",
  []
)

OpenGQL.Test.Repo
|> Ecto.Adapters.SQL.query!(
  """
  CREATE TABLE IF NOT EXISTS edges (
    source TEXT,
    target TEXT,
    rel TEXT,
    value TEXT,
    FOREIGN KEY(source) REFERENCES nodes(key),
    FOREIGN KEY(target) REFERENCES nodes(key)
  )
  """,
  []
)
