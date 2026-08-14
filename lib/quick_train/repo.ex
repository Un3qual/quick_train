defmodule QuickTrain.Repo do
  use Boundary, top_level?: true, deps: [], exports: []

  @dialyzer {:nowarn_function, all_tenants: 0}

  use AshPostgres.Repo,
    otp_app: :quick_train,
    warn_on_missing_ash_functions?: false

  def installed_extensions do
    ["ash-functions"]
  end

  def min_pg_version do
    %Version{major: 18, minor: 0, patch: 0}
  end
end
