defmodule QuickTrain.Application do
  use Boundary, top_level?: true, deps: [QuickTrain, QuickTrain.Repo, QuickTrainWeb]

  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_install_ecto_dev_logger()

    children =
      [
        QuickTrainWeb.Telemetry,
        QuickTrain.Repo,
        {DNSCluster, query: Application.get_env(:quick_train, :dns_cluster_query) || :ignore},
        {Oban, Application.fetch_env!(:quick_train, Oban)},
        {Phoenix.PubSub, name: QuickTrain.PubSub},
        {QuickTrain.Accounts.OidcBeginLimiter, clean_period: :timer.minutes(10)},
        QuickTrain.Accounts.OidcClientContextCache,
        QuickTrainWeb.Endpoint
      ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: QuickTrain.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    QuickTrainWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  if Code.ensure_loaded?(Ecto.DevLogger) do
    defp maybe_install_ecto_dev_logger, do: Ecto.DevLogger.install(QuickTrain.Repo)
  else
    defp maybe_install_ecto_dev_logger, do: :ok
  end
end
