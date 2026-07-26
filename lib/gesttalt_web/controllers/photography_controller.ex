defmodule GesttaltWeb.PhotographyController do
  use GesttaltWeb, :controller

  alias Gesttalt.Photography
  alias Gesttalt.Plans
  alias Gesttalt.Sites

  def index(conn, _params) do
    site = current_site(conn)

    render(conn, :index,
      page_title: "Photography",
      photos: Photography.list_photos(site),
      site: site
    )
  end

  def create(conn, %{"photo" => %{"file" => upload} = attrs}) do
    site = current_site(conn)

    with :ok <- Plans.authorize(site, :media_uploads),
         {:ok, photo} <- Photography.create_photo(site, upload, attrs) do
      message =
        if photo.status == :published,
          do: "Photo published.",
          else: "Photo saved as a draft."

      conn |> put_flash(:info, message) |> redirect(to: ~p"/admin/photography")
    else
      {:error, :subscription_required} ->
        conn
        |> put_flash(
          :error,
          dgettext("billing", "Upgrade to the Publisher plan to upload images.")
        )
        |> redirect(to: ~p"/admin/billing")

      {:error, :alt_text_required} ->
        conn
        |> put_flash(:error, "Describe the photo for people who cannot see it.")
        |> redirect(to: ~p"/admin/photography")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Photo could not be uploaded: #{inspect(reason)}")
        |> redirect(to: ~p"/admin/photography")
    end
  end

  def publish(conn, %{"id" => id}) do
    with {:ok, photo} <- Photography.fetch_photo(current_site(conn), id),
         {:ok, _photo} <- Photography.publish_photo(photo) do
      conn |> put_flash(:info, "Photo published.") |> redirect(to: ~p"/admin/photography")
    else
      result -> photo_action_error(conn, result)
    end
  end

  def unpublish(conn, %{"id" => id}) do
    with {:ok, photo} <- Photography.fetch_photo(current_site(conn), id),
         {:ok, _photo} <- Photography.unpublish_photo(photo) do
      conn
      |> put_flash(:info, "Photo moved to drafts.")
      |> redirect(to: ~p"/admin/photography")
    else
      result -> photo_action_error(conn, result)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Photography.delete_photo(current_site(conn), id) do
      {:ok, _photo} ->
        conn |> put_flash(:info, "Photo deleted.") |> redirect(to: ~p"/admin/photography")

      result ->
        photo_action_error(conn, result)
    end
  end

  defp photo_action_error(conn, {:error, :not_found}),
    do: send_resp(conn, :not_found, "Photo not found")

  defp photo_action_error(conn, {:error, reason}) do
    conn
    |> put_flash(:error, "Photo could not be changed: #{inspect(reason)}")
    |> redirect(to: ~p"/admin/photography")
  end

  defp current_site(conn) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    site
  end
end
