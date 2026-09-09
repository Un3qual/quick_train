defmodule QuickTrainWeb.DatasetRevisionGraphqlTest do
  use QuickTrain.ConnCase, async: false

  alias QuickTrain.{Accounts, Assets, Datasets}
  alias QuickTrain.Assets.Storage.InMemory, as: TestStorage

  setup %{conn: conn} do
    :ok = TestStorage.reset()

    manager = Accounts.register_user!("graphql-revisions@example.test", "GraphQL Revisions")

    graph =
      Accounts.bootstrap_first_manager!(manager.id, "graphql-revisions", "GraphQL Revisions")

    Datasets.grant_dataset_and_asset_capabilities!(graph.organization.id, manager.id)
    session = Accounts.issue_bearer_session!(manager.id)

    dataset =
      Datasets.create_dataset!(graph.organization.id, "customers", "Customers", actor: manager)

    schema = Datasets.create_schema_version!(graph.organization.id, dataset.id, actor: manager)

    root =
      Datasets.add_record_type!(graph.organization.id, schema.id, "customer", "Customer",
        actor: manager
      )

    field =
      Datasets.add_field_definition!(
        graph.organization.id,
        root.id,
        "name",
        "Name",
        "text",
        "single",
        true,
        actor: manager
      )

    asset_field =
      Datasets.add_field_definition!(
        graph.organization.id,
        root.id,
        "avatar",
        "Avatar",
        "asset",
        "single",
        false,
        actor: manager
      )

    asset = ready_asset!(graph.organization.id, manager, "avatar bytes")

    schema =
      Datasets.publish_schema_version!(graph.organization.id, schema.id, root.id, actor: manager)

    result =
      Datasets.put_item_revision!(
        graph.organization.id,
        dataset.id,
        schema.id,
        nil,
        "customer-1",
        [%{field: "name", text: "Alice"}, %{field: "avatar", asset_id: asset.id}],
        actor: manager
      )

    %{
      conn: put_req_header(conn, "authorization", "Bearer #{session.token}"),
      organization: graph.organization,
      dataset: dataset,
      field: field,
      asset_field: asset_field,
      asset: asset,
      result: result
    }
  end

  test "typed item, revision, and value reads are keyset Relay connections", context do
    data =
      graphql!(
        context.conn,
        """
        query TypedRevision(
          $organizationId: ID!,
          $datasetId: ID!,
          $itemId: ID!,
          $revisionId: ID!
        ) {
          datasets(organizationId: $organizationId, first: 1) {
            edges {
              cursor
              node {
                id
                items(first: 1) {
                  edges { cursor node { id externalKey } }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
          datasetItems(
            organizationId: $organizationId,
            datasetId: $datasetId,
            first: 1
          ) {
            edges {
              cursor
              node {
                id datasetId externalKey
                dataset { id key }
                revisions(first: 1) {
                  edges {
                    cursor
                    node {
                      id
                      item { id }
                      schemaVersion { id }
                      rootRecordType { id }
                      rootRecord {
                        recordType { id }
                        values(first: 2) {
                          edges {
                            cursor
                            node {
                              id
                              fieldDefinition { id key }
                              textValue { value }
                              assetValue { asset { id state } }
                            }
                          }
                          pageInfo { hasNextPage endCursor }
                        }
                      }
                    }
                  }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
          datasetItemRevisions(
            organizationId: $organizationId,
            itemId: $itemId,
            first: 1
          ) {
            edges {
              cursor
              node {
                id itemId schemaVersionId rootRecordTypeId rootRecordId revisionNumber fingerprint
              }
            }
            pageInfo { hasNextPage endCursor }
          }
          datasetValues(
            organizationId: $organizationId,
            revisionId: $revisionId,
            first: 2
          ) {
            edges {
              cursor
              node {
                id fieldDefinitionId ordinal
                fieldDefinition { id key }
                textValue { value }
                assetValue { asset { id state } }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
        """,
        %{
          "organizationId" => context.organization.id,
          "datasetId" => context.dataset.id,
          "itemId" => context.result.item.id,
          "revisionId" => context.result.revision.id
        }
      )

    assert [%{"cursor" => dataset_cursor, "node" => nested_dataset}] = data["datasets"]["edges"]

    assert hd(data["datasetItemRevisions"]["edges"])["node"]["fingerprint"] ==
             Base.encode16(context.result.revision.fingerprint, case: :lower)

    assert is_binary(dataset_cursor)
    assert nested_dataset["id"] == context.dataset.id

    assert [%{"cursor" => nested_item_cursor, "node" => nested_item}] =
             nested_dataset["items"]["edges"]

    assert is_binary(nested_item_cursor)
    assert nested_item["id"] == context.result.item.id
    assert nested_item["externalKey"] == "customer-1"
    refute nested_dataset["items"]["pageInfo"]["hasNextPage"]
    assert is_binary(nested_dataset["items"]["pageInfo"]["endCursor"])

    assert [%{"cursor" => item_cursor, "node" => item}] = data["datasetItems"]["edges"]
    assert is_binary(item_cursor)
    assert item["id"] == context.result.item.id
    assert item["externalKey"] == "customer-1"
    assert item["dataset"]["id"] == context.dataset.id

    assert [%{"cursor" => nested_revision_cursor, "node" => nested_revision}] =
             item["revisions"]["edges"]

    assert is_binary(nested_revision_cursor)
    assert nested_revision["id"] == context.result.revision.id
    assert nested_revision["item"]["id"] == context.result.item.id
    assert nested_revision["schemaVersion"]["id"] == context.result.revision.schema_version_id
    assert nested_revision["rootRecordType"]["id"] == context.result.revision.root_record_type_id

    assert nested_revision["rootRecord"]["recordType"]["id"] ==
             context.result.revision.root_record_type_id

    nested_values =
      Map.new(nested_revision["rootRecord"]["values"]["edges"], fn edge ->
        assert is_binary(edge["cursor"])
        {edge["node"]["fieldDefinition"]["key"], edge["node"]}
      end)

    assert nested_values["name"]["fieldDefinition"]["id"] == context.field.id
    assert nested_values["name"]["textValue"]["value"] == "Alice"
    assert nested_values["avatar"]["fieldDefinition"]["id"] == context.asset_field.id
    assert nested_values["avatar"]["assetValue"]["asset"]["id"] == context.asset.id
    assert nested_values["avatar"]["assetValue"]["asset"]["state"] == "READY"

    for connection <- [item["revisions"], nested_revision["rootRecord"]["values"]] do
      refute connection["pageInfo"]["hasNextPage"]
      assert is_binary(connection["pageInfo"]["endCursor"])
    end

    assert [%{"cursor" => revision_cursor, "node" => revision}] =
             data["datasetItemRevisions"]["edges"]

    assert is_binary(revision_cursor)
    assert revision["id"] == context.result.revision.id
    assert revision["revisionNumber"] == 1

    values =
      Map.new(data["datasetValues"]["edges"], fn edge ->
        assert is_binary(edge["cursor"])
        {edge["node"]["fieldDefinition"]["key"], edge["node"]}
      end)

    assert values["name"]["fieldDefinitionId"] == context.field.id
    assert values["name"]["ordinal"] == 0
    assert values["name"]["textValue"]["value"] == "Alice"
    assert values["avatar"]["fieldDefinitionId"] == context.asset_field.id
    assert values["avatar"]["assetValue"]["asset"]["id"] == context.asset.id

    for connection <- ~w(datasets datasetItems datasetItemRevisions datasetValues) do
      refute data[connection]["pageInfo"]["hasNextPage"]
      assert is_binary(data[connection]["pageInfo"]["endCursor"])
    end
  end

  defp ready_asset!(organization_id, manager, content) do
    registration =
      Assets.register_asset!(
        organization_id,
        Base.encode16(:crypto.hash(:sha256, content), case: :lower),
        byte_size(content),
        "text/plain",
        actor: manager
      )

    :ok = TestStorage.put_staging(registration.upload_access, content)
    Assets.finalize_asset!(registration.asset.id, organization_id, actor: manager).asset
  end
end
