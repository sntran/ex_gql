# Public Compatibility Test Suites (GQL/Cypher)

## Recommended Source

### openCypher TCK (Apache-2.0)
- Repository: https://github.com/opencypher/openCypher
- TCK index: `tck/index.adoc`
- Feature files: `tck/features/**`
- Useful feature groups for current OpenGQL scope:
  - `expressions/null/Null1.feature`, `Null2.feature`, `Null3.feature`
  - `expressions/precedence/Precedence1.feature`
  - `expressions/boolean/Boolean1.feature` .. `Boolean5.feature`
  - `expressions/comparison/Comparison1.feature`, `Comparison2.feature`
  - `expressions/string/String8.feature`, `String9.feature`, `String10.feature`
  - `clauses/match-where/MatchWhere5.feature`
  - `clauses/with-where/WithWhere5.feature`

## Secondary References

### Neo4j compatibility harnesses (implementation reference)
- Repository: https://github.com/neo4j/neo4j
- Relevant modules:
  - `community/cypher/compatibility-spec-suite`
  - `community/cypher/spec-suite-tools`
- These modules demonstrate how to run TCK scenarios and maintain deny-lists.

## Licensing Notes

- `opencypher/openCypher` is Apache-2.0 licensed and is suitable for scenario adaptation.
- Some Neo4j feature files in `neo4j/neo4j` are GPLv3; avoid copying GPL feature content into this repository unless that license impact is explicitly accepted.
- Practical approach for this repo: use openCypher TCK as canonical public source and re-express scenarios as ExUnit tests.

## Suggested Adoption Plan

1. Add a local mapping table from TCK scenario IDs to ExUnit tests in `test/opengql/tck_mapping_test.exs`.
2. Start with null-predicate and precedence scenarios that match current grammar support.
3. Mark unsupported scenarios with explicit reasons (missing grammar/runtime behavior).
4. Track pass-rate per imported scenario group in CI output.

## Current openCypher Alignment (Implemented)

The following OpenGQL tests are intentionally aligned to openCypher TCK scenario families:

- Null predicates (`IS NULL`, `IS NOT NULL`)
  - TCK families: `expressions/null/Null1.feature`, `Null2.feature`
  - Local tests: `test/opengql/parser_test.exs`, `test/opengql/query_builder_test.exs`, `test/opengql/integration_test.exs`

- Boolean and precedence (`NOT`, `AND`, `OR`, `XOR`, grouped expressions)
  - TCK families: `expressions/boolean/Boolean1.feature` .. `Boolean5.feature`, `expressions/precedence/Precedence1.feature`
  - Local tests: `test/opengql/parser_test.exs`, `test/opengql/query_builder_test.exs`, `test/opengql/integration_test.exs`

- Text predicates (`CONTAINS`, `STARTS WITH`, `ENDS WITH`)
  - TCK families: `expressions/string/String8.feature`, `String9.feature`, `String10.feature`
  - Local tests: `test/opengql/parser_test.exs`, `test/opengql/query_builder_test.exs`, `test/opengql/integration_test.exs`

- List/range-style filtering (`IN`, `NOT IN`, `BETWEEN`, `NOT BETWEEN`)
  - TCK families: `expressions/list/List5.feature` and comparison/precedence groups
  - Local tests: `test/opengql/parser_test.exs`, `test/opengql/query_builder_test.exs`, `test/opengql/integration_test.exs`

## Cypher-only vs OpenGQL Subset Notes

The list below differentiates clauses that are Cypher-specific in practice for this repository scope (or not implemented in this OpenGQL subset), even if some may exist in broader GQL standards work.

### Supported as Cypher-compat operators in this subset

- `XOR`
- `STARTS WITH`, `ENDS WITH`, `CONTAINS`
- `IS TRUE`, `IS FALSE`, `IS NOT TRUE`, `IS NOT FALSE`
- `SKIP` (mapped to SQL `OFFSET`)
- `FINISH` terminal marker

### Not implemented in this subset (Cypher-heavy feature areas)

- `WITH`, `UNWIND`, `OPTIONAL MATCH`
- `MERGE`, `CALL`, procedure/function invocation semantics
- Pattern comprehensions, quantified path patterns, shortest-path selectors
- Cypher transaction controls and runtime hints

When adding new compatibility tests, annotate each new case with one of:

- `openCypher-aligned`
- `OpenGQL-subset extension`
- `Cypher-only (out of scope)`
