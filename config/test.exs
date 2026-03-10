import Config

config :logger, level: :warning

config :opengql, OpenGQL.Test.Repo,
  database: ":memory:",
  pool_size: 1,
  log: false

config :opengql, ecto_repos: [OpenGQL.Test.Repo]
