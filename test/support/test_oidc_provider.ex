defmodule QuickTrain.TestOidcProvider do
  @moduledoc false

  @behaviour QuickTrain.Accounts.OidcProvider

  def authorization_url(options) do
    send(test_pid(), {:oidc_authorization, options})

    query =
      URI.encode_query(%{
        "redirect_uri" => options.redirect_uri,
        "state" => options.state,
        "nonce" => options.nonce,
        "code_challenge" => options.code_challenge,
        "code_challenge_method" => "S256"
      })

    {:ok, "https://issuer.example.test/authorize?#{query}"}
  end

  def exchange_code(code, options) do
    send(test_pid(), {:oidc_exchange, code, options})

    Application.get_env(
      :quick_train,
      :oidc_test_exchange_result,
      {:ok,
       %{
         "iss" => "https://issuer.example.test",
         "sub" => "subject-1",
         "email" => "New.User@Example.test",
         "email_verified" => true,
         "name" => "  New User  "
       }}
    )
  end

  defp test_pid, do: Application.fetch_env!(:quick_train, :oidc_test_pid)
end
