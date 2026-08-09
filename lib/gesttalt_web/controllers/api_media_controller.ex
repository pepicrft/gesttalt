defmodule GesttaltWeb.ApiMediaController do
  use GesttaltWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gesttalt.Sites

  tags ["Media"]
  security [%{"oauth2" => []}]
  plug GesttaltWeb.OAuthAuth, scopes: ["media:write"]

  operation :index,
    summary: "List images",
    responses: [
      ok:
        {"Images", "application/json",
         %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}}}
    ]

  operation :create,
    summary: "Upload an image",
    request_body:
      {"Multipart image upload", "multipart/form-data",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{
           file: %OpenApiSpex.Schema{type: :string, format: :binary},
           alt_text: %OpenApiSpex.Schema{type: :string}
         },
         required: [:file]
       }},
    responses: [created: {"Image", "application/json", %OpenApiSpex.Schema{type: :object}}]

  def index(conn, _params),
    do: json(conn, Enum.map(Sites.list_images(conn.assigns.current_site), &render_image/1))

  def create(conn, %{"file" => upload} = params) do
    case Sites.store_image(conn.assigns.current_site, upload, params["alt_text"]) do
      {:ok, image} ->
        conn |> put_status(:created) |> json(render_image(image))

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def create(conn, %{"image" => params}), do: create(conn, params)

  defp render_image(image),
    do: %{
      id: image.id,
      filename: image.filename,
      content_type: image.content_type,
      byte_size: image.byte_size,
      alt_text: image.alt_text,
      url: Sites.image_url(image)
    }
end
