# OpenGQL

An Elixir library for generating `Ecto.Query` using the
[Open Graph Query Language (GQL)](https://www.iso.org/standard/76120.html).

## Overview

OpenGQL provides a `~GQL` sigil (requires Elixir ≥ 1.15; use `~G` on Elixir 1.14)
that parses a subset of ISO GQL and returns an `Ecto.Query` ready to be executed
with your Ecto `Repo`.

The parser currently covers the **Match Pattern** subset:

| Pattern | Example |
|---------|---------|
| Node | `MATCH (a:Person) RETURN a` |
| Node with properties | `MATCH (a:Person {name: "Alice"}) RETURN a` |
| Directed right edge | `MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a, b` |
| Directed left edge | `MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN a, b` |
| Multiple patterns | `MATCH (a:Person), (b:Person) RETURN a, b` |

## Data Model

OpenGQL targets the following SQLite graph schema:

```sql
PRAGMA case_sensitive_like = true;

CREATE TABLE IF NOT EXISTS nodes (
  key   TEXT PRIMARY KEY NOT NULL, -- JSON serialized, either a string or [id, type]
  value TEXT -- JSON serialized body
);

CREATE INDEX IF NOT EXISTS key_idx ON nodes(key);

CREATE TABLE IF NOT EXISTS edges (
  source     TEXT,
  target     TEXT,
  rel        TEXT, -- the relationship type
  value      TEXT, -- properties of the edge, JSON serialized
  UNIQUE(source, target, value) ON CONFLICT REPLACE,
  FOREIGN KEY(source) REFERENCES nodes(key),
  FOREIGN KEY(target) REFERENCES nodes(key)
);

CREATE INDEX IF NOT EXISTS source_idx ON edges(source);
CREATE INDEX IF NOT EXISTS target_idx ON edges(target);
```

## Installation

```elixir
def deps do
  [
    {:opengql, github: "sntran/opengql"}
  ]
end
```

## Usage

```elixir
import OpenGQL

# Elixir >= 1.15 — multi-character sigil
query = ~GQL[MATCH (a:Person {name: "Alice"}) RETURN a]
Repo.all(query)

# Elixir 1.14 — single-character alias
query = ~G[MATCH (a:Person {name: "Alice"}) RETURN a]
Repo.all(query)

# Multi-line
query = ~GQL"""
  MATCH (a:Person {name: "Alice"})-[:KNOWS]->(b:Person)
  RETURN a, b
"""
Repo.all(query)
```

## Running Tests

```bash
mix deps.get
mix test
```
