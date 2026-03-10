defmodule OpenGQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :opengql,
      version: "0.1.0",
      elixir: "~> 1.14",
      compilers: [:yecc, :leex] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      deps: deps()
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Ecto and SQLite driver — dev/test only; not required at runtime
      {:ecto, git: "https://github.com/elixir-ecto/ecto.git", tag: "v3.12.5",
       only: [:dev, :test], override: true},
      {:ecto_sql, git: "https://github.com/elixir-ecto/ecto_sql.git", tag: "v3.12.1",
       only: [:dev, :test], override: true},
      {:ecto_sqlite3, git: "https://github.com/elixir-sqlite/ecto_sqlite3.git", tag: "v0.17.5",
       only: [:dev, :test]},
      {:stream_data, git: "https://github.com/whatyouhide/stream_data.git", tag: "v1.1.2",
       only: [:dev, :test]},
      {:excoveralls,
       git: "https://github.com/parroty/excoveralls.git", tag: "v0.18.3",
       only: :test},
      {:jason, git: "https://github.com/michalmuskala/jason.git", tag: "v1.4.4",
       only: :test, override: true}
    ]
  end
end
