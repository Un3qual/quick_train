defmodule QuickTrain do
  use Boundary,
    deps: [QuickTrain.Repo],
    exports: [
      Accounts,
      Accounts.Oidc,
      Authorization,
      EnterpriseIdentity,
      EnterpriseIdentity.Adapter,
      Integrations,
      Integrations.SecretStore,
      Operations,
      Organizations
    ]

  @moduledoc """
  Reusable enterprise backend foundations for organization-owned applications.
  """
end
