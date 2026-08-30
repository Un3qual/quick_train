defmodule QuickTrain.MixProject do
  use Mix.Project

  def project do
    [
      app: :quick_train,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_deps: :app_tree,
        plt_add_apps: [:ex_unit, :mix],
        flags: [:error_handling, :underspecs]
      ],
      listeners: [Phoenix.CodeReloader],
      usage_rules: usage_rules()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools, :inets, :ssl, :public_key],
      mod: {QuickTrain.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        verify: :test,
        "architecture.check": :test,
        "dependency.audit": :test,
        "static.analysis": :test,
        typecheck: :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "== 1.8.11"},
      {:phoenix_ecto, "== 4.7.0"},
      {:ecto_sql, "== 3.14.0"},
      {:postgrex, "== 0.22.4"},
      {:ash, "== 3.31.3"},
      {:ash_postgres, "== 2.11.0"},
      {:ash_graphql, "== 1.10.1"},
      {:absinthe, "== 1.11.0"},
      {:absinthe_relay, "== 1.6.0"},
      {:absinthe_plug, "== 1.5.10"},
      {:oidcc, "== 3.9.0"},
      {:req, "== 0.7.2"},
      {:hammer, "== 7.4.0"},
      {:oban, "== 2.24.0"},
      {:boundary, "== 0.10.4", runtime: false},
      {:credo, "== 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "== 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "== 1.5.4", only: [:dev, :test], runtime: false},
      {:ex_slop, "== 0.4.4", only: [:dev, :test], runtime: false},
      {:reach, "== 2.8.2", only: [:dev, :test], runtime: false},
      {:telemetry_metrics, "== 1.1.0"},
      {:telemetry_poller, "== 1.3.0"},
      {:jason, "== 1.4.5"},
      {:dns_cluster, "== 0.2.0"},
      {:bandit, "== 1.12.5"},
      {:ecto_dev_logger, "== 0.15.0", only: :dev},
      {:ash_diagram, "~> 0.2.2"},
      {:ex_cmd, "~> 0.18.0"},
      {:usage_rules, "~> 1.2", only: [:dev]},
      {:igniter, "~> 0.8.3", only: [:dev]},
      {:picosat_elixir, "~> 0.2.3"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "dependency.audit": ["cmd mix hex.audit"],
      "static.analysis": ["credo --strict", "reach.check --arch --smells --strict"],
      typecheck: ["dialyzer --quiet-with-result"],
      "architecture.check": [
        "xref graph --format cycles --label compile-connected --fail-above 0"
      ],
      "boundary.check": ["compile --force --warnings-as-errors"],
      "production.build": ["cmd env MIX_ENV=prod mix compile --warnings-as-errors"],
      verify: [
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "ash.codegen --check",
        "boundary.check",
        "architecture.check",
        "static.analysis",
        "typecheck",
        "dependency.audit",
        "production.build",
        "test"
      ],
      precommit: ["verify"]
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [],
      skills: [
        location: ".agents/skills",
        build: [
          ash: [
            description:
              "Use when editing Ash.Resource or Ash.Domain modules, actions, changes, validations, policies, queries, relationships, calculations, aggregates, migrations, or Ash tests.",
            usage_rules: [:ash]
          ],
          "ash-postgres": [
            description:
              "Use when configuring AshPostgres data layers, repositories, migrations, constraints, indexes, custom SQL, multitenancy, or PostgreSQL-backed Ash resources.",
            usage_rules: [:ash_postgres]
          ],
          "ash-graphql": [
            description:
              "Use when configuring AshGraphql domains or resources, GraphQL queries or mutations, custom GraphQL types, or the Ash and Absinthe API boundary.",
            usage_rules: [:ash_graphql, :absinthe, :absinthe_relay, :absinthe_plug]
          ],
          phoenix: [
            description:
              "Use when editing Phoenix endpoints, routers, plugs, controllers, channels, HTML components, LiveView, or Phoenix and Ecto integration.",
            usage_rules: [:phoenix, :phoenix_ecto]
          ],
          elixir: [
            description:
              "Use when writing or reviewing Elixir code, Mix tasks, tests, pattern matching, data structures, or error handling.",
            usage_rules: [{:usage_rules, main: false, sub_rules: ["elixir"]}]
          ],
          otp: [
            description:
              "Use when working with OTP processes, GenServer, supervisors, Task, process communication, fault tolerance, or application supervision trees.",
            usage_rules: [{:usage_rules, main: false, sub_rules: ["otp"]}]
          ],
          igniter: [
            description:
              "Use when writing or running Igniter installers, generators, project rewrites, or Igniter Mix tasks.",
            usage_rules: [:igniter]
          ],
          "usage-rules": [
            description:
              "Use when configuring, synchronizing, or troubleshooting usage_rules, generated AGENTS.md sections, dependency documentation search, or dependency-derived skills.",
            usage_rules: [{:usage_rules, sub_rules: []}]
          ]
        ]
      ]
    ]
  end
end
