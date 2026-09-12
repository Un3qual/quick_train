defmodule QuickTrain.Forms.Changes.AllocateVersion do
  @moduledoc false
  use Ash.Resource.Change
  alias QuickTrain.Forms
  alias QuickTrain.Forms.{Error, FormVersion}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &allocate/1)
  end

  defp allocate(changeset) do
    form_id = Ash.Changeset.get_attribute(changeset, :form_id)
    organization_id = Ash.Changeset.get_argument(changeset, :organization_id)
    form = Forms.lock_form!(form_id, organization_id, authorize?: false)
    if is_nil(form), do: Error.reject!(:invalid_form)

    number =
      Ash.max!(FormVersion, :version,
        query: [filter: [form_id: form.id]],
        default: 0,
        authorize?: false
      ) + 1

    Ash.Changeset.force_change_attribute(changeset, :version, number)
  rescue
    error in Ash.Error.Invalid -> Ash.Changeset.add_error(changeset, error)
  end
end
