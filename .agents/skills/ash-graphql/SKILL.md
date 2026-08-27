---
name: ash-graphql
description: "Use when configuring AshGraphql domains or resources, GraphQL queries or mutations, custom GraphQL types, or the Ash and Absinthe API boundary."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

### ash_graphql

- [ash_graphql](references/ash_graphql/ash_graphql.md)
- [custom_types](references/ash_graphql/custom_types.md)
- [domain_configuration](references/ash_graphql/domain_configuration.md)
- [resource_configuration](references/ash_graphql/resource_configuration.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p ash_graphql -p absinthe -p absinthe_relay -p absinthe_plug
```

## Available Mix Tasks

- `mix ash_graphql.install` - Installs AshGraphql. Should be run with `mix igniter.install ash_graphql`
- `mix absinthe.schema.json` - Generate a schema.json file for an Absinthe schema
- `mix absinthe.schema.json.options`
- `mix absinthe.schema.sdl` - Generate a schema.graphql file for an Absinthe schema
- `mix absinthe.schema.sdl.options`
- `mix absinthe.plug.graphiql.assets.download` - Download GraphiQL assets
- `mix absinthe.plug.graphiql.assets.remove` - Removes GraphiQL assets
<!-- usage-rules-skill-end -->
