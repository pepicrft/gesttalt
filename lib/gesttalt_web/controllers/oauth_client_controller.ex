defmodule GesttaltWeb.OAuthClientController do
  use GesttaltWeb, :controller

  alias Gesttalt.OAuth.ClientsManager

  def index(conn, _params),
    do:
      render(conn, :index,
        page_title: "Connected applications",
        clients: ClientsManager.list_clients(user(conn)),
        created_client: nil
      )

  def create(conn, %{"client" => attrs}) do
    case ClientsManager.create_client(user(conn), attrs) do
      {:ok, client} ->
        render(conn, :index,
          page_title: "Connected applications",
          clients: ClientsManager.list_clients(user(conn)),
          created_client: client
        )

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Client could not be created: #{format_errors(changeset)}")
        |> redirect(to: ~p"/admin/oauth-clients")
    end
  end

  def delete(conn, %{"id" => id}) do
    ClientsManager.delete_client(user(conn), id)
    conn |> put_flash(:info, "Client deleted.") |> redirect(to: ~p"/admin/oauth-clients")
  end

  defp user(conn), do: conn.assigns.current_scope.user
  defp format_errors(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp format_errors(reason), do: inspect(reason)
end
