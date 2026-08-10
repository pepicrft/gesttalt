defmodule GesttaltWeb.ApiIdeaController do
  use GesttaltWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.IdeaJSON
  alias GesttaltWeb.API.Schemas.{Idea, IdeaParams}

  tags ["Ideas"]
  security [%{"oauth2" => []}]

  plug GesttaltWeb.OAuthAuth, [scopes: ["content:read"]] when action in [:index, :show]
  plug GesttaltWeb.OAuthAuth, [scopes: ["content:write"]] when action not in [:index, :show]

  operation :index,
    summary: "List ideas",
    responses: [ok: {"Ideas", "application/json", %OpenApiSpex.Schema{type: :array, items: Idea}}]

  operation :show,
    summary: "Get an idea",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [ok: {"Idea", "application/json", Idea}]

  operation :create,
    summary: "Create an idea",
    request_body: {"Idea", "application/json", IdeaParams},
    responses: [created: {"Created idea", "application/json", Idea}]

  operation :update,
    summary: "Update an idea",
    parameters: [id: [in: :path, type: :integer, required: true]],
    request_body: {"Idea", "application/json", IdeaParams},
    responses: [ok: {"Updated idea", "application/json", Idea}]

  operation :delete,
    summary: "Delete an idea",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, _params),
    do: json(conn, Enum.map(Publishing.list_ideas(site(conn)), &IdeaJSON.render/1))

  def show(conn, %{"id" => id}),
    do: json(conn, site(conn) |> Publishing.get_idea!(id) |> IdeaJSON.render())

  def create(conn, params) do
    case Publishing.create_idea(site(conn), idea_params(params)) do
      {:ok, idea} -> conn |> put_status(:created) |> json(IdeaJSON.render(idea))
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    idea = Publishing.get_idea!(site(conn), id)

    case Publishing.update_idea(idea, idea_params(params)) do
      {:ok, idea} -> json(conn, IdeaJSON.render(idea))
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    site(conn) |> Publishing.get_idea!(id) |> Publishing.delete_idea()
    send_resp(conn, :no_content, "")
  end

  defp idea_params(%{"idea" => params}), do: params
  defp idea_params(params), do: Map.drop(params, ["id"])
  defp site(conn), do: conn.assigns.current_site

  defp changeset_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      errors: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    })
  end
end
