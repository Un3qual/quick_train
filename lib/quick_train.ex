defmodule QuickTrain do
  use Boundary,
    deps: [QuickTrain.Repo],
    exports: [
      Accounts,
      Accounts.Oidc,
      Assets,
      Assets.Storage,
      Authorization,
      Datasets,
      EnterpriseIdentity,
      EnterpriseIdentity.Adapter,
      Organizations
    ]

  @moduledoc """
  Reusable enterprise backend foundations for organization-owned applications.
  """
end
