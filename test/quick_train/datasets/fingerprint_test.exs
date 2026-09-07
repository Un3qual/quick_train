defmodule QuickTrain.Datasets.FingerprintTest do
  use ExUnit.Case, async: true

  test "version-one fingerprints retain their persisted encoding across all value families" do
    alias QuickTrain.Datasets.{ImportRowFingerprint, RevisionFingerprint}
    schema = "00000000-0000-4000-8000-000000000001"
    root = "00000000-0000-4000-8000-000000000002"

    entries = [
      %{field: "text", family: :text, value: "héllo"},
      %{field: "integer", family: :integer, value: -42},
      %{field: "decimal", family: :decimal, value: Decimal.new("1.2300")},
      %{field: "boolean", family: :boolean, value: false},
      %{field: "time", family: :utc_datetime, value: ~U[2026-01-02 03:04:05.123456Z]},
      %{field: "asset", family: :asset, value: "00000000-0000-4000-8000-000000000003"}
    ]

    occurrences =
      Enum.with_index(entries, 10)
      |> Enum.map(fn {entry, i} ->
        Map.merge(entry, %{field: %{id: "00000000-0000-4000-8000-0000000000#{i}"}, ordinal: 0})
      end)

    assert RevisionFingerprint.encode(schema, root, occurrences) ==
             "82d067f516fa8fa3f198d4b5313d349bdfadcbeaec4d72c7da1545c68827efde"

    assert ImportRowFingerprint.encode(schema, "row", nil, 7, entries) ==
             "dce99f4a9aebd285f7afb124fef86a1c3c0731bbaa4eaf2e0da8c728d5b86ee6"
  end
end
