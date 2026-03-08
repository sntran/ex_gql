defmodule OpenGQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :opengql,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:nimble_parsec, git: "https://github.com/dashbitco/nimble_parsec.git", tag: "v1.4.0"},
      {:ecto, git: "https://github.com/elixir-ecto/ecto.git", tag: "v3.12.5"},
      {:decimal, git: "https://github.com/ericmj/decimal.git", tag: "v2.3.0", override: true},
      {:telemetry, git: "https://github.com/beam-telemetry/telemetry.git", tag: "v1.3.0",
       override: true},
      {:stream_data, git: "https://github.com/whatyouhide/stream_data.git", tag: "v1.1.2",
       only: [:dev, :test]}
    ]
  end
end
