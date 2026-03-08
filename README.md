# OpenGQL

An Elixir library for querying a SQLite graph database using a subset of the
[Open Graph Query Language (GQL)](https://www.iso.org/standard/76120.html).

## Overview

OpenGQL is **Ecto-free at the library level**.  The `~GQL` / `~G` sigils
compile a GQL string into an `%OpenGQL.Statement{}` containing plain SQL + its
bound parameters.  You execute the statement with any SQLite connection using
`OpenGQL.execute/2` — including Ecto repos.

## Data Model

OpenGQL targets the following SQLite graph schema:

```sql
CREATE TABLE nodes (
  key   TEXT PRIMARY KEY NOT NULL, -- JSON: string or ["id", "Label"]
  value TEXT                       -- JSON: property map
);

CREATE TABLE edges (
  source TEXT REFERENCES nodes(key),
  target TEXT REFERENCES nodes(key),
  rel    TEXT,   -- relationship type
  value  TEXT    -- JSON: edge properties
);
```

## Installation

```elixir
def deps do
  [
    {:opengql, github: "sntran/opengql"}
  ]
end
```

> **Note** — OpenGQL has only one runtime dependency: `nimble_parsec`.  Ecto
> and all SQLite adapters are optional; they are only used in the tests bundled
> with this library.

## Usage

```elixir
import OpenGQL

# --- MATCH + RETURN ---
# Returns %OpenGQL.Statement{type: :select}
stmt = ~G"MATCH (a:Person {name: \"Alice\"})-[:KNOWS]->(b:Person) RETURN a, b"
{:ok, rows} = OpenGQL.execute(stmt, &MyRepo.query/2)
# rows => [%{"n1_key" => "[\"alice\",\"Person\"]", "n1_value" => "...",
#             "n2_key" => "[\"bob\",\"Person\"]",  "n2_value" => "..."}]

# --- CREATE ---
# Returns %OpenGQL.Statement{type: :insert}
stmt = ~G"CREATE (a:Person {name: \"Alice\"})-[:KNOWS]->(b:Person {name: \"Bob\"})"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

# --- MATCH + SET ---
# Returns %OpenGQL.Statement{type: :update}
stmt = ~G"MATCH (a:Person) SET a.active = true"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

# --- MATCH + DELETE ---
# Returns %OpenGQL.Statement{type: :delete}
stmt = ~G"MATCH (a:Person) DELETE a"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

# --- MATCH + DETACH DELETE (removes edges first, then nodes) ---
stmt = ~G"MATCH (a:Person) DETACH DELETE a"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)
```

## Supported GQL Patterns

| Pattern                                   | Example GQL                                              |
|-------------------------------------------|----------------------------------------------------------|
| Node by label                             | `MATCH (a:Person) RETURN a`                              |
| Node with properties                      | `MATCH (a:Person {name: "Alice"}) RETURN a`              |
| Right-directed edge                       | `MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b`     |
| Left-directed edge                        | `MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b`     |
| Multiple comma-separated patterns         | `MATCH (a:Person), (b:Person) RETURN a, b`              |
| Create node                               | `CREATE (a:Person {name: "Alice"})`                     |
| Create nodes and edge                     | `CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})` |
| Update properties                         | `MATCH (a:Person) SET a.age = 30`                       |
| Delete matched nodes                      | `MATCH (a:Person) DELETE a`                             |
| Detach delete (remove edges + node)       | `MATCH (a:Person) DETACH DELETE a`                      |
| Compound: match then create               | `MATCH (a:Person), (b:Person) CREATE (a)-[:FRIENDS_WITH]->(b)` |

## Return Types

| GQL clause(s)           | Statement type  | `execute/2` returns          |
|-------------------------|-----------------|------------------------------|
| `MATCH … RETURN`        | `:select`       | `{:ok, [%{col => val}]}`     |
| `CREATE …`              | `:insert`       | `{:ok, [result_per_op]}`     |
| `MATCH … SET`           | `:update`       | `{:ok, result}`              |
| `MATCH … DELETE`        | `:delete`       | `{:ok, result}`              |
| `MATCH … DETACH DELETE` | `:delete`       | `{:ok, result}`              |

### SELECT column names

- Single-node query (`MATCH (a:…) RETURN a`): columns `"key"`, `"value"`
- Path / cross-join query (`RETURN a, b`): columns `"n1_key"`, `"n1_value"`, `"n2_key"`, `"n2_value"`

## `OpenGQL.execute/2`

```elixir
OpenGQL.execute(statement, query_fn)
```

`query_fn` is any `(sql, params) -> {:ok, result} | {:error, reason}` function.
For Ecto repos pass `&MyRepo.query/2`.

## Elixir Version Compatibility

| Sigil   | Minimum Elixir |
|---------|----------------|
| `~GQL`  | 1.15 (multi-character sigils) |
| `~G`    | 1.14           |

## Running Tests

```bash
mix deps.get
mix test
```
