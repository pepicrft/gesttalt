defmodule GesttaltWeb.ThemePreviewController do
  use GesttaltWeb, :controller

  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing
  alias GesttaltWeb.ThemePreviewLive
  alias Phoenix.LiveView.Controller, as: LiveViewController

  def home(conn, %{"session_id" => session_id}) do
    render_preview(conn, session_id, %{"kind" => "home"})
  end

  def article(conn, %{"session_id" => session_id, "slug" => slug}) do
    render_preview(conn, session_id, %{"kind" => "article", "slug" => slug})
  end

  def page(conn, %{"session_id" => session_id, "slug" => slug}) do
    render_preview(conn, session_id, %{"kind" => "page", "slug" => slug})
  end

  def media(conn, %{"session_id" => session_id, "id" => image_id}) do
    with_session(conn, session_id, fn _session, site ->
      image = Sites.get_image!(site, image_id)

      case Sites.fetch_image(image) do
        {:ok, body} ->
          conn
          |> put_resp_content_type(image.content_type)
          |> put_resp_header("cache-control", "private, no-store")
          |> put_resp_header("referrer-policy", "no-referrer")
          |> send_resp(200, body)

        {:error, _reason} ->
          not_found(conn)
      end
    end)
  end

  defp with_session(conn, session_id, callback) do
    case ThemeEditing.fetch(session_id) do
      {:ok, session} -> callback.(session, Sites.get_site!(session.site_id))
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp render_preview(conn, session_id, page) do
    with_session(conn, session_id, fn session, site ->
      live_session = %{
        "page" => page,
        "session_id" => session.id,
        "site_id" => site.id
      }

      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("x-robots-tag", "noindex, nofollow")
      |> LiveViewController.live_render(ThemePreviewLive,
        session: live_session,
        container: {:main, id: "theme-preview-live"}
      )
    end)
  end

  defp not_found(conn),
    do: conn |> put_status(:not_found) |> text("Theme editing session not found or expired.")
end
