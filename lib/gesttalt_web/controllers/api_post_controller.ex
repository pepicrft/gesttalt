defmodule GesttaltWeb.ApiPostController do
  use GesttaltWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.PostJSON
  alias GesttaltWeb.API.Schemas.{Post, PostParams}

  tags ["Content"]
  security [%{"oauth2" => []}]

  plug GesttaltWeb.OAuthAuth, [scopes: ["content:read"]] when action in [:index, :show]
  plug GesttaltWeb.OAuthAuth, [scopes: ["content:write"]] when action not in [:index, :show]

  operation :index,
    summary: "List posts and pages",
    responses: [
      ok: {"Content", "application/json", %OpenApiSpex.Schema{type: :array, items: Post}}
    ]

  operation :show,
    summary: "Get a post or page",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [ok: {"Content", "application/json", Post}]

  operation :create,
    summary: "Create a post or page",
    request_body: {"Content", "application/json", PostParams},
    responses: [created: {"Created content", "application/json", Post}]

  operation :update,
    summary: "Update a post or page",
    parameters: [id: [in: :path, type: :integer, required: true]],
    request_body: {"Content", "application/json", PostParams},
    responses: [ok: {"Updated content", "application/json", Post}]

  operation :delete,
    summary: "Delete a post or page",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [no_content: "Deleted"]

  operation :publish,
    summary: "Publish content",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [ok: {"Published content", "application/json", Post}]

  operation :unpublish,
    summary: "Return content to drafts",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [ok: {"Draft content", "application/json", Post}]

  def index(conn, _params),
    do: json(conn, Enum.map(Publishing.list_posts(site(conn)), &PostJSON.render/1))

  def show(conn, %{"id" => id}),
    do: json(conn, site(conn) |> Publishing.get_post!(id) |> PostJSON.render())

  def create(conn, params) do
    case Publishing.create_post(site(conn), content_params(params)) do
      {:ok, post} -> conn |> put_status(:created) |> json(PostJSON.render(post))
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    post = Publishing.get_post!(site(conn), id)

    case Publishing.update_post(post, content_params(params)) do
      {:ok, post} -> json(conn, PostJSON.render(post))
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    site(conn) |> Publishing.get_post!(id) |> Publishing.delete_post()
    send_resp(conn, :no_content, "")
  end

  def publish(conn, %{"id" => id}) do
    {:ok, post} = site(conn) |> Publishing.get_post!(id) |> Publishing.publish_post()
    json(conn, PostJSON.render(post))
  end

  def unpublish(conn, %{"id" => id}) do
    {:ok, post} = site(conn) |> Publishing.get_post!(id) |> Publishing.unpublish_post()
    json(conn, PostJSON.render(post))
  end

  defp content_params(%{"post" => params}), do: params
  defp content_params(params), do: Map.drop(params, ["id"])
  defp site(conn), do: conn.assigns.current_site

  defp changeset_error(conn, changeset),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        errors: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
      })
end
