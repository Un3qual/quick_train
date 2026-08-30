defmodule Mix.Tasks.QuickTrain.BootstrapFirstManager do
  @moduledoc "Bootstraps the first organization manager from an existing active global user."

  use Boundary, classify_to: QuickTrain.Mix
  use Mix.Task

  @shortdoc "Bootstrap the first organization manager"
  @requirements ["app.start"]

  @switches [user_id: :string, organization_slug: :string, organization_name: :string]

  @impl Mix.Task
  def run(argv) do
    with {options, [], []} <- OptionParser.parse(argv, strict: @switches),
         {:ok, user_id} <- Keyword.fetch(options, :user_id),
         {:ok, organization_slug} <- Keyword.fetch(options, :organization_slug),
         {:ok, organization_name} <- Keyword.fetch(options, :organization_name),
         {:ok, graph} <-
           QuickTrain.Accounts.bootstrap_first_manager(
             user_id,
             organization_slug,
             organization_name,
             authorize?: false
           ) do
      Mix.shell().info(
        "Bootstrapped manager #{graph.user.id} for organization #{graph.organization.slug}"
      )
    else
      _invalid ->
        Mix.raise(
          "bootstrap failed; provide --user-id UUID --organization-slug SLUG --organization-name NAME and ensure the exact active graph is nonconflicting"
        )
    end
  end
end
