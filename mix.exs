defmodule OpenGQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :opengql,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:nimble_parsec, git: "https://github.com/dashbitco/nimble_parsec.git", tag: "v1.4.0"},
      {:ecto, git: "https://github.com/elixir-ecto/ecto.git", tag: "v3.12.5", override: true},
      {:ecto_sql, git: "https://github.com/elixir-ecto/ecto_sql.git", tag: "v3.12.1",
       override: true},
      {:ecto_sqlite3, git: "https://github.com/elixir-sqlite/ecto_sqlite3.git", tag: "v0.17.5"},
      {:exqlite, git: "https://github.com/elixir-sqlite/exqlite.git", tag: "v0.29.0",
       override: true},
      {:db_connection, git: "https://github.com/elixir-ecto/db_connection.git", tag: "v2.7.0",
       override: true},
      {:elixir_make, git: "https://github.com/elixir-lang/elixir_make.git", tag: "v0.9.0",
       runtime: false, override: true},
      {:cc_precompiler,
       git: "https://github.com/cocoa-xu/cc_precompiler.git", tag: "v0.1.9",
       runtime: false, override: true},
      {:decimal, git: "https://github.com/ericmj/decimal.git", tag: "v2.3.0", override: true},
      {:telemetry, git: "https://github.com/beam-telemetry/telemetry.git", tag: "v1.3.0",
       override: true},
      {:stream_data, git: "https://github.com/whatyouhide/stream_data.git", tag: "v1.1.2",
       only: [:dev, :test]}
    ]
  end
end
