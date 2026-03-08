defmodule OpenGQL.Statement do
  @moduledoc """
  Represents a compiled GQL statement — the output of the `~GQL` / `~G` sigil.

  A `Statement` holds everything needed to execute a GQL operation against any
  SQLite-compatible database, with **no Ecto dependency**.

  ## Fields

  - `:type` — the operation kind: `:select`, `:insert`, `:update`, or `:delete`
  - `:operations` — ordered list of `{sql, params}` tuples to run

  ## Types and their `operations`

  | `:type`    | Produced by               | `operations` count |
  |------------|---------------------------|--------------------|
  | `:select`  | `MATCH … RETURN`          | 1                  |
  | `:insert`  | `CREATE …`               | 1 per node + edge  |
  | `:update`  | `MATCH … SET`             | 1                  |
  | `:delete`  | `MATCH … DELETE`          | 1                  |
  | `:delete`  | `MATCH … DETACH DELETE`   | 2 (edges, nodes)   |

  ## Usage

  Use `OpenGQL.execute/2` to run a statement against any SQLite connection:

      stmt = ~G"MATCH (a:Person {name: \"Alice\"}) RETURN a"
      {:ok, rows} = OpenGQL.execute(stmt, &MyRepo.query/2)
      # rows => [%{"key" => "[\"alice\",\"Person\"]", "value" => "{\"name\":\"Alice\"}"}]

  The `query_fn` argument must be a 2-arity function that accepts `(sql, params)` and returns
  `{:ok, result}` or `{:error, reason}`.  For SELECT results the `result` must have
  `columns` and `rows` fields (compatible with `Ecto.Repo.query/2` and most DB drivers).
  """

  @type operation_type :: :select | :insert | :update | :delete
  @type sql_op :: {sql :: String.t(), params :: list()}

  @enforce_keys [:type, :operations]
  defstruct [:type, :operations]

  @type t :: %__MODULE__{
          type: operation_type(),
          operations: [sql_op()]
        }
end
