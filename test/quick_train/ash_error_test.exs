defmodule QuickTrain.AshErrorTest do
  use ExUnit.Case, async: true

  alias Ash.Error.Changes.InvalidAttribute
  alias QuickTrain.{AshError, DatasetAssetError}

  test "finds structured failures through nested classes regardless of overlapping paths" do
    constraint =
      InvalidAttribute.exception(
        field: :external_key,
        message: "already exists",
        private_vars: [constraint: "dataset_items_dataset_external_key_index"],
        path: [:rows]
      )

    reason = DatasetAssetError.exception(category: :stale_asset_claim, path: [:rows, 0])

    for leaves <- [[constraint, reason], [reason, constraint]] do
      error = Ash.Error.Invalid.exception(errors: [Ash.Error.Invalid.exception(errors: leaves)])

      assert AshError.constraint?(error, ["dataset_items_dataset_external_key_index"])
      assert AshError.reason?(error, :stale_asset_claim)
      refute AshError.constraint?(error, ["other_constraint"])
      refute AshError.reason?(error, :staging_missing)
    end
  end

  test "classifies leaf errors and lists without matching message text" do
    constraint =
      InvalidAttribute.exception(
        field: :id,
        message: "stale_asset_claim",
        private_vars: %{constraint: "assets_sealed_key_index"}
      )

    assert AshError.constraint?(constraint, ["assets_sealed_key_index"])
    assert AshError.constraint?([constraint], ["assets_sealed_key_index"])
    refute AshError.reason?(constraint, :stale_asset_claim)
    refute AshError.constraint?([], ["assets_sealed_key_index"])
  end
end
