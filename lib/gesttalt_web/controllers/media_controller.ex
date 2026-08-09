defmodule GesttaltWeb.MediaController do
  use GesttaltWeb, :controller

  alias Gesttalt.Sites

  def index(conn, _params) do
    site = current_site(conn)
    render(conn, :index, page_title: "Media", site: site, images: Sites.list_images(site))
  end

  def create(conn, %{"image" => %{"file" => upload} = attrs}) do
    site = current_site(conn)

    with {:ok, _image} <- Sites.store_image(site, upload, attrs["alt_text"]) do
      conn |> put_flash(:info, "Image uploaded.") |> redirect(to: ~p"/admin/media")
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Image could not be uploaded: #{inspect(reason)}")
        |> redirect(to: ~p"/admin/media")
    end
  end

  def show(conn, %{"id" => id}) do
    image = Sites.get_image!(current_site(conn), id)

    case Sites.fetch_image(image) do
      {:ok, body} ->
        conn
        |> put_resp_content_type(image.content_type)
        |> put_resp_header("cache-control", "private, max-age=3600")
        |> send_resp(200, body)

      {:error, _reason} ->
        send_resp(conn, :not_found, "Media not found")
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
