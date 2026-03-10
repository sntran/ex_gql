defmodule OpenGQL.Test.Repo do
  use Ecto.Repo,
    otp_app: :opengql,
    adapter: Ecto.Adapters.SQLite3
end
