defmodule GesttaltWeb.ApiPhotoController do
  use GesttaltWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gesttalt.Photography
  alias Gesttalt.Photography.PhotoJSON
  alias GesttaltWeb.API.Schemas.Photo

  tags ["Photography"]
  security [%{"oauth2" => []}]

  plug GesttaltWeb.OAuthAuth, [scopes: ["content:read"]] when action in [:index, :show]
  plug GesttaltWeb.OAuthAuth, [scopes: ["media:write"]] when action not in [:index, :show]

  operation :index,
    summary: "List photography feed entries",
    responses: [
      ok: {"Photos", "application/json", %OpenApiSpex.Schema{type: :array, items: Photo}}
    ]

  operation :show,
    summary: "Get a photography feed entry",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [ok: {"Photo", "application/json", Photo}]

  operation :create,
    summary: "Upload a photography feed entry",
    request_body:
      {"Multipart photo upload", "multipart/form-data",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{
           file: %OpenApiSpex.Schema{type: :string, format: :binary},
           alt_text: %OpenApiSpex.Schema{type: :string},
           caption: %OpenApiSpex.Schema{type: :string},
           status: %OpenApiSpex.Schema{type: :string, enum: ["draft", "published"]}
         },
         required: [:file, :alt_text]
       }},
    responses: [created: {"Photo", "application/json", Photo}]

  operation :update,
    summary: "Update a photography feed caption",
    parameters: [id: [in: :path, type: :integer, required: true]],
    request_body:
      {"Photo changes", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{caption: %OpenApiSpex.Schema{type: :string}}
       }},
    responses: [ok: {"Photo", "application/json", Photo}]

  operation :delete,
    summary: "Delete a photography feed entry and its image",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [no_content: "Deleted"]

  operation :publish,
    summary: "Publish a photography feed entry",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [ok: {"Photo", "application/json", Photo}]

  operation :unpublish,
    summary: "Return a photography feed entry to drafts",
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [ok: {"Photo", "application/json", Photo}]

  def index(conn, _params),
    do: json(conn, Enum.map(Photography.list_photos(site(conn)), &PhotoJSON.render/1))

  def show(conn, %{"id" => id}) do
    case Photography.fetch_photo(site(conn), id) do
      {:ok, photo} -> json(conn, PhotoJSON.render(photo))
      {:error, reason} -> error_response(conn, reason)
    end
  end

  def create(conn, %{"file" => upload} = params) do
    params = Map.put_new(params, "status", "draft")

    case Photography.create_photo(site(conn), upload, params) do
      {:ok, photo} ->
        conn |> put_status(:created) |> json(PhotoJSON.render(photo))

      {:error, reason} ->
        error_response(conn, reason)
    end
  end

  def create(conn, %{"photo" => params}), do: create(conn, params)

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "photo", Map.drop(params, ["id"]))

    with {:ok, photo} <- Photography.fetch_photo(site(conn), id),
         {:ok, photo} <- Photography.update_photo(photo, attrs) do
      json(conn, PhotoJSON.render(photo))
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Photography.delete_photo(site(conn), id) do
      {:ok, _photo} -> send_resp(conn, :no_content, "")
      {:error, reason} -> error_response(conn, reason)
    end
  end

  def publish(conn, %{"id" => id}) do
    with {:ok, photo} <- Photography.fetch_photo(site(conn), id),
         {:ok, photo} <- Photography.publish_photo(photo) do
      json(conn, PhotoJSON.render(photo))
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  def unpublish(conn, %{"id" => id}) do
    with {:ok, photo} <- Photography.fetch_photo(site(conn), id),
         {:ok, photo} <- Photography.unpublish_photo(photo) do
      json(conn, PhotoJSON.render(photo))
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  defp site(conn), do: conn.assigns.current_site

  defp error_response(conn, :not_found),
    do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  defp error_response(conn, reason),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
end
