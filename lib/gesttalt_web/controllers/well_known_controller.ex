defmodule GesttaltWeb.WellKnownController do
  use GesttaltWeb, :controller

  alias Gesttalt.AgentAuth

  @scopes ~w(content:read content:write media:write mcp)

  def scopes, do: @scopes

  def authorization_server(conn, _params) do
    origin = GesttaltWeb.Endpoint.url()

    json(conn, %{
      resource: origin,
      resource_name: "Gesttalt publishing",
      resource_logo_uri: origin <> "/images/logo.svg",
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
      issuer: origin,
      authorization_endpoint: origin <> "/oauth2/authorize",
      token_endpoint: origin <> "/oauth2/token",
      revocation_endpoint: origin <> "/oauth2/revoke",
      introspection_endpoint: origin <> "/oauth2/introspect",
      registration_endpoint: origin <> "/oauth2/register",
      grant_types_supported: [
        "authorization_code",
        "refresh_token",
        AgentAuth.claim_grant(),
        AgentAuth.jwt_bearer_grant()
      ],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: @scopes,
      resource_documentation: origin <> "/docs",
      token_endpoint_auth_methods_supported: ["none", "client_secret_basic", "client_secret_post"],
      jwks_uri: origin <> "/.well-known/jwks.json",
      agent_auth: %{
        skill: origin <> "/auth.md",
        identity_endpoint: origin <> "/agent/identity",
        claim_endpoint: origin <> "/agent/identity/claim",
        identity_types_supported: ["service_auth"]
      }
    })
  end

  def protected_resource(conn, _params) do
    origin = GesttaltWeb.Endpoint.url()

    json(conn, %{
      resource: origin,
      resource_name: "Gesttalt publishing",
      resource_logo_uri: origin <> "/images/logo.svg",
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
      scopes_supported: @scopes,
      resource_documentation: origin <> "/docs"
    })
  end

  def mcp_protected_resource(conn, _params) do
    origin = GesttaltWeb.Endpoint.url()

    json(conn, %{
      resource: origin <> "/mcp",
      resource_name: "Gesttalt Model Context Protocol publishing server",
      resource_logo_uri: origin <> "/images/logo.svg",
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
      scopes_supported: @scopes,
      resource_documentation: origin <> "/docs#mcp"
    })
  end

  def jwks(conn, _params) do
    case AgentAuth.jwks() do
      {:ok, keys} ->
        json(conn, keys)

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "signing_key_unavailable"})
    end
  end

  def mcp_server_card(conn, _params) do
    origin = GesttaltWeb.Endpoint.url()

    json(conn, %{
      name: "Gesttalt",
      description: "Create and publish posts, pages, and photography feeds from an agent.",
      version: "1.0.0",
      transport: %{
        type: "streamable-http",
        url: origin <> "/mcp",
        protocol_versions: ["2025-06-18", "2025-03-26"]
      },
      authentication: %{
        type: "oauth2",
        protected_resource_metadata: origin <> "/.well-known/oauth-protected-resource/mcp",
        agent_registration: origin <> "/auth.md"
      }
    })
  end
end
