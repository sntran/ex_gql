import Config

config :opengql, OpenGQL.Test.Repo,
  database: ":memory:",
  pool_size: 1

config :opengql, ecto_repos: [OpenGQL.Test.Repo]
