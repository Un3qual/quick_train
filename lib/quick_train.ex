defmodule QuickTrain do
  use Boundary,
    deps: [QuickTrain.Repo],
    exports: [
      Accounts,
      Accounts.Oidc,
      Audit,
      Authorization,
      DurableDelivery,
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
