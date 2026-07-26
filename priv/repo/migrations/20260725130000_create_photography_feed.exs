defmodule Gesttalt.Repo.Migrations.CreatePhotographyFeed do
  use Ecto.Migration

  def up do
    alter table(:themes) do
      add :photography_template, :text
    end

    alter table(:theme_editing_sessions) do
      add :photography_template, :text
    end

    create table(:photos) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :image_id, references(:images, on_delete: :delete_all), null: false
      add :caption, :text
      add :status, :string, null: false, default: "draft"
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:photos, [:image_id])
    create index(:photos, [:site_id, :status, :published_at])
  end

  def down do
    drop table(:photos)

    alter table(:theme_editing_sessions) do
      remove :photography_template
    end

    alter table(:themes) do
      remove :photography_template
    end
  end
end
