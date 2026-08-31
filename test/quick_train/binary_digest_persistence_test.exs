defmodule QuickTrain.BinaryDigestPersistenceTest do
  use QuickTrain.DataCase, async: true

  @digest_columns [
    {"assets", "sha256"},
    {"dataset_import_rows", "fingerprint"},
    {"dataset_imports", "open_fingerprint"},
    {"dataset_item_revisions", "fingerprint"},
    {"oidc_login_transactions", "nonce_hash"},
    {"oidc_login_transactions", "redemption_secret_hash"},
    {"oidc_login_transactions", "state_hash"},
    {"sessions", "token_hash"}
  ]

  test "cryptographic digests use native binary columns" do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name, column_name, data_type
      FROM information_schema.columns
      WHERE table_schema = current_schema()
      """)

    column_types =
      Map.new(rows, fn [table_name, column_name, data_type] ->
        {{table_name, column_name}, data_type}
      end)

    assert Map.take(column_types, @digest_columns) ==
             Map.new(@digest_columns, &{&1, "bytea"})
  end
end
