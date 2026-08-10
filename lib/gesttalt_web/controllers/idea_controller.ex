defmodule GesttaltWeb.IdeaController do
  use GesttaltWeb, :controller

  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.Idea
  alias Gesttalt.Sites

  def index(conn, _params), do: render_index(conn, Publishing.change_idea(%Idea{}))

  def create(conn, %{"idea" => attrs}) do
    case Publishing.create_idea(current_site(conn), attrs) do
      {:ok, _idea} ->
        conn |> put_flash(:info, "Idea saved.") |> redirect(to: ~p"/admin/ideas")

      {:error, changeset} ->
        render_index(conn, changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    idea = Publishing.get_idea!(current_site(conn), id)

    render(conn, :edit,
      page_title: "Edit idea",
      changeset: Publishing.change_idea(idea),
      idea: idea
    )
  end

  def update(conn, %{"id" => id, "idea" => attrs}) do
    idea = Publishing.get_idea!(current_site(conn), id)

    case Publishing.update_idea(idea, attrs) do
      {:ok, _idea} ->
        conn |> put_flash(:info, "Idea saved.") |> redirect(to: ~p"/admin/ideas")

      {:error, changeset} ->
        render(conn, :edit, page_title: "Edit idea", changeset: changeset, idea: idea)
    end
  end

  def delete(conn, %{"id" => id}) do
    current_site(conn) |> Publishing.get_idea!(id) |> Publishing.delete_idea()
    conn |> put_flash(:info, "Idea deleted.") |> redirect(to: ~p"/admin/ideas")
  end

  defp render_index(conn, changeset) do
    render(conn, :index,
      page_title: "Ideas",
      changeset: changeset,
      ideas: Publishing.list_ideas(current_site(conn))
    )
  end

  defp current_site(conn) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    site
  end
end
