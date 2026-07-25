defmodule GesttaltWeb.OpenGraphController do
  @moduledoc """
  Serves theme-matched Open Graph images for the current publication.

  The image is rendered lazily on the first request and proxied from durable
  object storage on every later request. Requests must carry a valid signature
  minted by `Gesttalt.OpenGraph`, otherwise no render happens.
  """

  use GesttaltWeb, :controller

  alias Gesttalt.OpenGraph

  def show(%{assigns: %{current_site: nil}} = conn, _params),
    do: conn |> put_status(:not_found) |> text("Not found")

  def show(%{assigns: %{current_site: site}} = conn, params) do
    if OpenGraph.verify_signature(params) do
      serve(conn, site, params)
    else
      conn |> put_status(:forbidden) |> text("Invalid signature")
    end
  end

  defp serve(conn, site, params) do
    case OpenGraph.render(site, params) do
      {:ok, bytes} ->
        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_resp(200, bytes)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text("Not found")

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> text("Image could not be rendered: #{inspect(reason)}")
    end
  end
end
