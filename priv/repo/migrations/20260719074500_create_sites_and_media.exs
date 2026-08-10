defmodule Gesttalt.Repo.Migrations.CreateSitesAndMedia do
  use Ecto.Migration

  def change do
    create table(:sites) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :handle, :string, null: false
      add :tagline, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sites, [:user_id])
    create unique_index(:sites, [:handle])

    create table(:domains) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :hostname, :string, null: false
      add :kind, :string, null: false, default: "custom"
      add :status, :string, null: false, default: "pending"
      add :verification_token, :string, null: false
      add :verified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:domains, [:hostname])
    create index(:domains, [:site_id])

    create table(:themes) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :index_template, :text, null: false
      add :article_template, :text, null: false
      add :page_template, :text, null: false
      add :stylesheet, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:themes, [:site_id])

    create table(:images) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :storage_key, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :alt_text, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:images, [:storage_key])
    create index(:images, [:site_id])

    drop unique_index(:posts, [:slug])

    alter table(:posts) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "post"
    end

    create unique_index(:posts, [:site_id, :slug])
    create index(:posts, [:site_id, :kind, :status, :published_at])
  end
end
