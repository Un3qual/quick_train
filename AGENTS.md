# QuickTrain agent instructions

## IMPORTANT
I like ambitious ideas, simple systems, and software that feels obvious. Do not preserve complexity just because it already exists. Do not introduce machinery because it looks architecturally impressive. Understand the real constraint, then fight for the smallest model that makes the correct behavior unsurprising.

Channel both "measure twice, cut once" and "yagni". Fight scope creep. Try to honor the dev's intent in both a minimal and realistic fashion.

## General instructions
- Use `mise` for the repository toolchain.
- Keep the backend on stable/GA dependency releases and update `.mise.toml`, `mix.exs`, and the
  lockfile together.
- Preserve the single global `User` model. Organization membership is relational and optional;
  all sessions still require an account.
- Keep authorization fail-closed and explicitly scoped to an organization.
- Run `mise run verify` before merging changes.
- Channel YAGNI when writing code. A simpler solution is always better.
- If Elixir, Ash, or another library has a built-in way to accomplish something, use that rather than hand-rolling a solution.

## OpenSpec
- Use OpenSpec for durable specifications and implementation plans. Do not create
  `docs/superpowers` or another parallel planning tree.
- Keep proposals, specs, designs, tasks, and implementation synchronized as a change evolves.
- Run `mise run openspec.validate` to validate all OpenSpec artifacts independently.

## Ash First
- Always use Ash concepts, almost never Ecto concepts directly. Think hard about the "Ash way" to do things. If you don't know, look for information in the rules & docs of Ash & associated packages.

## Code Generation
- Start with generators wherever possible. They provide a starting point for your code and can be modified if needed.

## Logs & Tests
- When you're done executing code, try to compile the code, and check the logs or run any applicable tests to see what effect your changes have had.
- Don't add unnecessary regression tests for every single review comment. Analyze whether it is worth adding a regression test before blindly adding one when the issue may just be something like a one time typo or mistake.
- Don't write tests that detect if code has been changed (or not changed)
- Overall, be deliberate about each test you add and consider if it is actually needed, if it will prevent future issues, etc.
