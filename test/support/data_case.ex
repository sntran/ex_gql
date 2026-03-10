defmodule OpenGQL.DataCase do
  @moduledoc """
  Test case template for integration tests that require a real SQLite database.

  Provides aliases for `Repo`, `Node`, and `Edge` and cleans all data before
  each test so tests remain isolated.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias OpenGQL.Test.Repo
      alias OpenGQL.Test.Node
      alias OpenGQL.Test.Edge
      import Ecto.Query
      import OpenGQL
    end
  end

  setup do
    OpenGQL.Test.Repo.delete_all(OpenGQL.Test.Edge)
    OpenGQL.Test.Repo.delete_all(OpenGQL.Test.Node)
    :ok
  end
end
