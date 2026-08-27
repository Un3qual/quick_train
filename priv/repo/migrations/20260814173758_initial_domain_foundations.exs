defmodule QuickTrain.Repo.Migrations.InitialDomainFoundations do
  @moduledoc """
  Creates the initial QuickTrain application schema.
  """

  use Ecto.Migration

  def up do
    create table(:users, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :email, :text, null: false
      add :display_name, :text, null: false
      add :status, :text, null: false, default: "active"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:users, [:email], name: "users_email_index")

    create table(:sessions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :organization_id, :uuid
      add :authentication_method, :text, null: false, default: "oidc"
      add :token_hash, :text
      add :issued_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "sessions_user_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create table(:roles, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :organization_id, :uuid, null: false
      add :key, :text, null: false
      add :name, :text, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:roles, [:organization_id, :key], name: "roles_organization_key_index")

    create table(:role_capabilities, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :role_id, :uuid, null: false
      add :capability_id, :uuid, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:role_capabilities, [:role_id, :capability_id],
             name: "role_capabilities_role_capability_index"
           )

    create table(:role_assignments, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :organization_id, :uuid, null: false
      add :user_id, :uuid, null: false
      add :role_id, :uuid, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:role_assignments, [:organization_id, :user_id, :role_id],
             name: "role_assignments_organization_user_role_index"
           )

    create table(:organizations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:organizations) do
      add :name, :text, null: false
      add :slug, :text, null: false
      add :status, :text, null: false, default: "active"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:organizations, [:slug], name: "organizations_slug_index")

    create table(:organization_memberships, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :text, null: false, default: "active"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :organization_id,
          references(:organizations,
            column: :id,
            name: "organization_memberships_organization_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :user_id,
          references(:users,
            column: :id,
            name: "organization_memberships_user_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:organization_memberships, [:organization_id, :user_id],
             name: "organization_memberships_organization_user_index"
           )

    create table(:oidc_login_transactions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :state_hash, :text, null: false
      add :code_verifier, :text, null: false
      add :return_to, :text, null: false, default: "/"
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:oidc_login_transactions, [:state_hash],
             name: "oidc_login_transactions_state_hash_index"
           )

    create table(:external_identities, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :provider, :text, null: false
      add :subject, :text, null: false
      add :status, :text, null: false, default: "active"
      add :claims, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "external_identities_user_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:external_identities, [:provider, :subject],
             name: "external_identities_provider_subject_index"
           )

    create unique_index(:external_identities, [:user_id, :provider],
             name: "external_identities_user_provider_index"
           )

    create table(:external_group_role_mappings, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :directory_group_id, :uuid, null: false
      add :role_id, :uuid, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:external_group_role_mappings, [:directory_group_id, :role_id],
             name: "external_group_role_mappings_group_role_index"
           )

    create table(:enterprise_connections, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :organization_id, :uuid, null: false
      add :provider, :text, null: false
      add :external_id, :text, null: false
      add :status, :text, null: false, default: "active"
      add :configuration, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:enterprise_connections, [:provider, :external_id],
             name: "enterprise_connections_provider_external_index"
           )

    create table(:directory_users, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :enterprise_connection_id, :uuid, null: false
      add :membership_id, :uuid, null: false
      add :user_id, :uuid, null: false
      add :external_id, :text, null: false
      add :status, :text, null: false, default: "active"
      add :profile, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:directory_users, [:enterprise_connection_id, :external_id],
             name: "directory_users_enterprise_connection_external_index"
           )

    create table(:directory_memberships, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :directory_user_id, :uuid, null: false
      add :directory_group_id, :uuid, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:directory_memberships, [:directory_user_id, :directory_group_id],
             name: "directory_memberships_user_group_index"
           )

    create table(:directory_groups, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :directory_id, :uuid, null: false
      add :external_id, :text, null: false
      add :name, :text, null: false
      add :status, :text, null: false, default: "active"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:directory_groups, [:directory_id, :external_id],
             name: "directory_groups_directory_external_index"
           )

    create table(:directories, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :enterprise_connection_id, :uuid, null: false
      add :external_id, :text, null: false
      add :status, :text, null: false, default: "active"
      add :last_synced_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:directories, [:enterprise_connection_id, :external_id],
             name: "directories_enterprise_connection_external_index"
           )

    create table(:capabilities, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :key, :text, null: false
      add :description, :text, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:capabilities, [:key], name: "capabilities_key_index")

    create table(:authorization_decisions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :user_id, :uuid, null: false
      add :organization_id, :uuid, null: false
      add :capability, :text, null: false
      add :allowed, :boolean, null: false
      add :reason, :text, null: false
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create table(:authentication_events, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :user_id, :uuid
      add :organization_id, :uuid
      add :event, :text, null: false
      add :result, :text, null: false
      add :reason, :text
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    alter table(:sessions) do
      modify :organization_id,
             references(:organizations,
               column: :id,
               name: "sessions_organization_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:roles) do
      modify :organization_id,
             references(:organizations,
               column: :id,
               name: "roles_organization_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:role_capabilities) do
      modify :role_id,
             references(:roles,
               column: :id,
               name: "role_capabilities_role_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :capability_id,
             references(:capabilities,
               column: :id,
               name: "role_capabilities_capability_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:role_assignments) do
      modify :organization_id,
             references(:organizations,
               column: :id,
               name: "role_assignments_organization_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :user_id,
             references(:users,
               column: :id,
               name: "role_assignments_user_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :role_id,
             references(:roles,
               column: :id,
               name: "role_assignments_role_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:external_group_role_mappings) do
      modify :directory_group_id,
             references(:directory_groups,
               column: :id,
               name: "external_group_role_mappings_directory_group_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :role_id,
             references(:roles,
               column: :id,
               name: "external_group_role_mappings_role_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:enterprise_connections) do
      modify :organization_id,
             references(:organizations,
               column: :id,
               name: "enterprise_connections_organization_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:directory_users) do
      modify :enterprise_connection_id,
             references(:enterprise_connections,
               column: :id,
               name: "directory_users_enterprise_connection_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :membership_id,
             references(:organization_memberships,
               column: :id,
               name: "directory_users_membership_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :user_id,
             references(:users,
               column: :id,
               name: "directory_users_user_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:directory_memberships) do
      modify :directory_user_id,
             references(:directory_users,
               column: :id,
               name: "directory_memberships_directory_user_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :directory_group_id,
             references(:directory_groups,
               column: :id,
               name: "directory_memberships_directory_group_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:directory_groups) do
      modify :directory_id,
             references(:directories,
               column: :id,
               name: "directory_groups_directory_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:directories) do
      modify :enterprise_connection_id,
             references(:enterprise_connections,
               column: :id,
               name: "directories_enterprise_connection_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:authorization_decisions) do
      modify :user_id,
             references(:users,
               column: :id,
               name: "authorization_decisions_user_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :organization_id,
             references(:organizations,
               column: :id,
               name: "authorization_decisions_organization_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:authentication_events) do
      modify :user_id,
             references(:users,
               column: :id,
               name: "authentication_events_user_id_fkey",
               type: :uuid,
               prefix: "public"
             )

      modify :organization_id,
             references(:organizations,
               column: :id,
               name: "authentication_events_organization_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end
  end

  def down do
    drop table(:authentication_events)
    drop table(:authorization_decisions)
    drop table(:external_group_role_mappings)
    drop table(:directory_memberships)
    drop table(:directory_users)
    drop table(:directory_groups)
    drop table(:directories)
    drop table(:enterprise_connections)
    drop table(:role_assignments)
    drop table(:role_capabilities)
    drop table(:roles)
    drop table(:capabilities)
    drop table(:external_identities)
    drop table(:oidc_login_transactions)
    drop table(:sessions)
    drop table(:organization_memberships)
    drop table(:organizations)
    drop table(:users)
  end
end
