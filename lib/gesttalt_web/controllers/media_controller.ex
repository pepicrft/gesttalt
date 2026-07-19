defmodule GesttaltWeb.MediaController do
  use GesttaltWeb, :controller

  alias Gesttalt.Plans
  alias Gesttalt.Sites

  def index(conn, _params) do
    site = current_site(conn)
    render(conn, :index, page_title: "Media", site: site, images: Sites.list_images(site))
  end

  def create(conn, %{"image" => %{"file" => upload} = attrs}) do
    site = current_site(conn)

    with :ok <- Plans.authorize(site, :media_uploads),
         {:ok, _image} <- Sites.store_image(site, upload, attrs["alt_text"]) do
      conn |> put_flash(:info, "Image uploaded.") |> redirect(to: ~p"/admin/media")
    else
      {:error, :subscription_required} ->
        conn
        |> put_flash(
          :error,
          dgettext("billing", "Upgrade to the Publisher plan to upload images.")
        )
        |> redirect(to: ~p"/admin/billing")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Image could not be uploaded: #{inspect(reason)}")
        |> redirect(to: ~p"/admin/media")
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _image} = Sites.delete_image(current_site(conn), id)
    conn |> put_flash(:info, "Image deleted.") |> redirect(to: ~p"/admin/media")
  end

  defp current_site(conn) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    site
  end
end
