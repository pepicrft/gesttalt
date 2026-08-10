defmodule GesttaltWeb.AnalyticsController do
  use GesttaltWeb, :controller

  alias Gesttalt.Analytics
  alias Gesttalt.Analytics.Location

  def create(%{assigns: %{current_site: nil}} = conn, _params),
    do: send_resp(conn, :not_found, "")

  def create(%{assigns: %{current_site: site}} = conn, %{"path" => path}) do
    case Analytics.record_page_view(site, %{path: path, country: Location.country(conn)}) do
      {:ok, _page_view} -> send_resp(conn, :no_content, "")
      {:error, _changeset} -> send_resp(conn, :unprocessable_entity, "")
    end
  end

  def create(conn, _params), do: send_resp(conn, :unprocessable_entity, "")
end
