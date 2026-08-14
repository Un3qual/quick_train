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
        plt_add_apps: [:ex_unit],
        flags: [:error_handling, :underspecs]
      ],
      listeners: [Phoenix.CodeReloader]
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
        "migration.drift": :test,
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
      {:ash_graphql, "== 1.10.0"},
      {:absinthe, "== 1.11.0"},
      {:absinthe_relay, "== 1.6.0"},
      {:absinthe_plug, "== 1.5.10"},
      {:oidcc, "== 3.8.0"},
      {:req, "== 0.7.2"},
      {:oban, "== 2.23.1"},
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
      {:bandit, "== 1.12.4"},
      {:ecto_dev_logger, "== 0.15.0", only: :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "migration.drift": ["ash_postgres.generate_migrations --check"],
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
        "migration.drift",
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
end
