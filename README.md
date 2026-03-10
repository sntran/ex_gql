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

> **Note** — OpenGQL itself has no required runtime dependency beyond the Erlang
> / Elixir standard tooling used to build it. Ecto and SQLite adapters are
> optional; they are only used in the tests bundled with this library.

## Usage

### Via `OpenGQL.execute/2` (adapter-agnostic)

```elixir
import OpenGQL

# --- MATCH + RETURN ---
# Returns %OpenGQL.Statement{type: :select}
stmt = ~G"MATCH (a:Person)-[:KNOWS]->(b:Person) WHERE a.age >= 21 RETURN a, b ORDER BY a.age DESC LIMIT 10 OFFSET 0"
{:ok, rows} = OpenGQL.execute(stmt, &MyRepo.query/2)
# rows => [%{"n1_key" => "[\"alice\",\"Person\"]", "n1_value" => "...",
#             "n2_key" => "[\"bob\",\"Person\"]",  "n2_value" => "..."}]

# --- CREATE ---
# Returns %OpenGQL.Statement{type: :insert}
stmt = ~G"CREATE (a:Person {name: \"Alice\"})-[:KNOWS]->(b:Person {name: \"Bob\"})"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

# --- MATCH + SET ---
stmt = ~G"MATCH (a:Person) SET a.active = true"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

# --- MATCH + DELETE ---
stmt = ~G"MATCH (a:Person) DELETE a"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)

# --- MATCH + DETACH DELETE (removes edges first, then nodes) ---
stmt = ~G"MATCH (a:Person) DETACH DELETE a"
{:ok, _} = OpenGQL.execute(stmt, &MyRepo.query/2)
```

### Via `Repo.all/2` (Ecto.Queryable)

SELECT (`MATCH … RETURN`) statements implement the `Ecto.Queryable` protocol via
`test/support/queryable.ex`, which is compiled in `:dev` and `:test` environments.
This lets you pass a statement directly to `Repo.all/2`:

```elixir
import OpenGQL

# Pass the Statement directly to Repo.all — returns the same string-keyed maps
# as OpenGQL.execute/2
results = Repo.all(~G"MATCH (a:Person) RETURN a")
# results => [%{"key" => "[\"alice\",\"Person\"]", "value" => "{\"name\":\"Alice\"}"}]

# With property filters
results = Repo.all(~G[MATCH (a:Person {name: "Alice"}) RETURN a])

# Path queries
results = Repo.all(~G"MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b")
# results => [%{"n1_key" => "...", "n1_value" => "...", "n2_key" => "...", "n2_value" => "..."}]
```

## Supported GQL Patterns

| Pattern                                   | Example GQL                                              |
|-------------------------------------------|----------------------------------------------------------|
| Node by label                             | `MATCH (a:Person) RETURN a`                              |
| Node with properties                      | `MATCH (a:Person {name: "Alice"}) RETURN a`              |
| Right-directed edge                       | `MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b`     |
| Left-directed edge                        | `MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b`     |
| WHERE predicate on properties             | `MATCH (a:Person) WHERE a.age >= 21 RETURN a`           |
| FILTER predicate on properties            | `MATCH (a:Person) FILTER a.name = "Alice" RETURN a`    |
| Boolean predicates (`AND`/`OR`/`XOR`/`NOT`) | `MATCH (a:Person) WHERE NOT a.active = 1 XOR a.staff = 1 RETURN a` |
| Grouped predicate expressions             | `MATCH (a:Person) WHERE (a.age >= 21 OR a.name = "Bob") AND a.active = 1 RETURN a` |
| Null predicates                           | `MATCH (a:Person) WHERE a.ref IS NULL RETURN a`         |
| Boolean-state predicates                  | `MATCH (a:Person) WHERE a.active IS NOT TRUE RETURN a` |
| Set/list predicates                       | `MATCH (a:Person) WHERE a.name IN ["Alice", "Bob"] RETURN a` |
| Text predicates                           | `MATCH (a:Person) WHERE a.name CONTAINS "li" RETURN a` |
| ORDER BY                                  | `MATCH (a:Person) RETURN a ORDER BY a.age DESC`         |
| LIMIT / OFFSET / SKIP                     | `MATCH (a:Person) RETURN a LIMIT 10 OFFSET 20`          |
| FINISH (terminal marker)                  | `MATCH (a:Person) RETURN a FINISH`                      |
| Multiple comma-separated patterns         | `MATCH (a:Person), (b:Person) RETURN a, b`              |
| Create node                               | `CREATE (a:Person {name: "Alice"})`                     |
| Create nodes and edge                     | `CREATE (a:Person {name: "Alice"})-[:KNOWS]->(b:Person {name: "Bob"})` |
| Update properties                         | `MATCH (a:Person) SET a.age = 30`                       |
| Delete matched nodes                      | `MATCH (a:Person) DELETE a`                             |
| Detach delete (remove edges + node)       | `MATCH (a:Person) DETACH DELETE a`                      |
| Compound: match then create               | `MATCH (a:Person), (b:Person) CREATE (a)-[:FRIENDS_WITH]->(b)` |

## Return Types

| GQL clause(s)           | Statement type  | `execute/2` returns          | `Repo.all/2` |
|-------------------------|-----------------|------------------------------|--------------|
| `MATCH … RETURN`        | `:select`       | `{:ok, [%{col => val}]}`     | ✅ supported |
| `CREATE …`              | `:insert`       | `{:ok, [result_per_op]}`     | ❌ use `execute/2` |
| `MATCH … SET`           | `:update`       | `{:ok, result}`              | ❌ use `execute/2` |
| `MATCH … DELETE`        | `:delete`       | `{:ok, result}`              | ❌ use `execute/2` |
| `MATCH … DETACH DELETE` | `:delete`       | `{:ok, result}`              | ❌ use `execute/2` |

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

## Compatibility Suites

For public GQL/Cypher conformance inputs and adoption notes, see:

- `docs/compatibility_suites.md`
