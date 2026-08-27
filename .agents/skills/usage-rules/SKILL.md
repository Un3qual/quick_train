---
name: usage-rules
description: "Use when configuring, synchronizing, or troubleshooting usage_rules, generated AGENTS.md sections, dependency documentation search, or dependency-derived skills."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

### usage_rules

- [usage_rules](references/usage_rules/usage_rules.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p usage_rules
```

## Available Mix Tasks

- `mix usage_rules.docs` - Shows documentation for Elixir modules and functions
- `mix usage_rules.install` - Installs usage_rules
- `mix usage_rules.install.docs`
- `mix usage_rules.list` - Lists usage-rules.md and sub-rules (usage-rules/*.md) for dependencies
- `mix usage_rules.search_docs` - Searches hexdocs with human-readable output
- `mix usage_rules.sync` - Sync AGENTS.md and agent skills from project config
- `mix usage_rules.sync.docs`
<!-- usage-rules-skill-end -->
