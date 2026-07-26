defmodule GesttaltWeb.API.Spec do
  @moduledoc "The OpenAPI document for every supported publishing endpoint."

  @behaviour OpenApiSpex.OpenApi

  alias GesttaltWeb.Router
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}

  @impl true
  def spec do
    %OpenApi{
      info: %Info{
        title: "Gesttalt publishing interface",
        version: "1.0.0",
        description:
          "Create and manage publications, photography feeds, and images from any authorized client."
      },
      servers: [%Server{url: GesttaltWeb.Endpoint.url()}],
      components: %Components{
        securitySchemes: %{
          "oauth2" => %SecurityScheme{
            type: "oauth2",
            flows: %{
              authorizationCode: %{
                authorizationUrl: "/oauth2/authorize",
                tokenUrl: "/oauth2/token",
                scopes: %{
                  "content:read" => "Read posts, pages, and photography feed entries",
                  "content:write" => "Create and edit posts and pages",
                  "media:write" => "Manage images and photography feed entries"
                }
              }
            }
          }
        }
      },
      security: [%{"oauth2" => []}],
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
