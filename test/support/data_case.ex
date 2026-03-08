defmodule OpenGQL.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias OpenGQL.Test.Repo
      alias OpenGQL.Schema.Node
      alias OpenGQL.Schema.Edge
      import Ecto.Query
      import OpenGQL
    end
  end

  setup do
    OpenGQL.Test.Repo.delete_all(OpenGQL.Schema.Edge)
    OpenGQL.Test.Repo.delete_all(OpenGQL.Schema.Node)
    :ok
  end
end
