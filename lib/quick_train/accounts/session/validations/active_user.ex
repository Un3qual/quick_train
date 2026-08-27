defmodule QuickTrain.Accounts.Session.Validations.ActiveUser do
  @moduledoc false

  use Ash.Resource.Validation

  alias QuickTrain.Accounts
  alias QuickTrain.Accounts.User

  @impl true
  def validate(changeset, _opts, _context) do
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    case Accounts.get_user(user_id, authorize?: false) do
      {:ok, %User{status: "active"}} -> :ok
      _other -> {:error, field: :user_id, message: "account required"}
    end
  end
end
