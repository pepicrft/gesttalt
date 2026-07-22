defmodule GesttaltWeb.AgentAuthTest do
  use GesttaltWeb.ConnCase, async: false

  import Ecto.Query

  alias Boruta.Ecto.Scope
  alias Gesttalt.Accounts
  alias Gesttalt.AccountsFixtures
  alias Gesttalt.AgentAuth.Event
  alias Gesttalt.Publishing
  alias Gesttalt.Repo
  alias Gesttalt.Sites

  @claim_grant "urn:workos:agent-auth:grant-type:claim"
  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @scope_names ~w(content:read content:write media:write mcp)

  setup do
    Enum.each(@scope_names, fn name ->
      %Scope{}
      |> Scope.changeset(%{name: name, label: name, public: true})
      |> Repo.insert!(on_conflict: :nothing)
    end)

    :ok
  end

  test "registers, claims, and publishes through the Model Context Protocol", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)

    registration = register_agent(conn, user.email)

    pending =
      conn
      |> recycle()
      |> post(~p"/oauth2/token", %{
        "grant_type" => @claim_grant,
        "claim_token" => registration["claim_token"]
      })
      |> json_response(400)

    assert pending["error"] == "authorization_pending"

    claim_path = verification_path(registration)

    claim_page =
      conn
      |> recycle()
      |> log_in_user(user)
      |> get(claim_path)

    assert html_response(claim_page, 200) =~ "Confirm agent access"

    confirmation =
      claim_page
      |> recycle()
      |> log_in_user(user)
      |> post(~p"/agent/identity/claim/confirm", %{
        "claim_attempt_token" => query_value(claim_path, "claim_attempt_token"),
        "user_code" => registration["claim"]["user_code"]
      })

    assert html_response(confirmation, 200) =~ "Access confirmed"

    token_response =
      conn
      |> recycle()
      |> post(~p"/oauth2/token", %{
        "grant_type" => @claim_grant,
        "claim_token" => registration["claim_token"]
      })
      |> json_response(200)

    assert token_response["token_type"] == "Bearer"
    assert token_response["scope"] == Enum.join(@scope_names, " ")
    assert token_response["identity_assertion"]
    access_token = token_response["access_token"]

    initialize =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/mcp",
        JSON.encode!(%{
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: %{protocolVersion: "2025-06-18", capabilities: %{}}
        })
      )

    assert json_response(initialize, 200)["result"]["protocolVersion"] == "2025-06-18"
    assert [session_id] = get_resp_header(initialize, "mcp-session-id")
    assert is_binary(session_id)

    created =
      call_tool(conn, access_token, 2, "create_content", %{
        title: "Published by an agent",
        body: "The complete Auth.md flow works.",
        status: "published"
      })

    assert created["title"] == "Published by an agent"
    assert created["status"] == "published"
    assert [%{title: "Published by an agent"}] = Publishing.list_posts(site)

    refreshed =
      conn
      |> recycle()
      |> post(~p"/oauth2/token", %{
        "grant_type" => @jwt_bearer_grant,
        "assertion" => token_response["identity_assertion"],
        "resource" => GesttaltWeb.Endpoint.url() <> "/mcp"
      })
      |> json_response(200)

    assert refreshed["access_token"] != access_token
    assert Repo.aggregate(Event, :count) >= 7

    revoke_response =
      conn
      |> recycle()
      |> post(~p"/oauth2/revoke", %{
        "token" => access_token,
        "token_type_hint" => "access_token"
      })

    assert response(revoke_response, 200) == ""

    revoked_request =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/mcp", JSON.encode!(%{jsonrpc: "2.0", id: 5, method: "tools/list"}))

    assert json_response(revoked_request, 401)["error"] == "invalid_token"
    assert Repo.exists?(from event in Event, where: event.name == "token.revoked")
  end

  test "creates the requested account before sending the user to sign in", %{conn: conn} do
    email = "agent-created-#{System.unique_integer([:positive])}@example.com"
    registration = register_agent(conn, email)
    claim_path = verification_path(registration)

    response = conn |> recycle() |> get(claim_path)

    assert redirected_to(response) == ~p"/users/log-in?email=#{email}"
    assert Accounts.get_user_by_email(email)
  end

  test "publishes discovery documents and rejects unsupported protocol versions", %{conn: conn} do
    metadata = conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(200)

    assert metadata["agent_auth"]["skill"] == GesttaltWeb.Endpoint.url() <> "/auth.md"
    assert metadata["agent_auth"]["identity_types_supported"] == ["service_auth"]

    assert metadata["agent_auth"]["claim_endpoint"] ==
             GesttaltWeb.Endpoint.url() <> "/agent/identity/claim"

    assert metadata["resource"] == GesttaltWeb.Endpoint.url()
    assert metadata["resource_logo_uri"] == GesttaltWeb.Endpoint.url() <> "/images/logo.svg"
    assert @claim_grant in metadata["grant_types_supported"]
    assert @jwt_bearer_grant in metadata["grant_types_supported"]

    protected =
      conn
      |> recycle()
      |> get(~p"/.well-known/oauth-protected-resource/mcp")
      |> json_response(200)

    assert protected["resource"] == GesttaltWeb.Endpoint.url() <> "/mcp"

    server_card =
      conn
      |> recycle()
      |> get(~p"/.well-known/mcp/server-card.json")
      |> json_response(200)

    assert server_card["transport"]["url"] == GesttaltWeb.Endpoint.url() <> "/mcp"

    auth_document = conn |> recycle() |> get(~p"/auth.md") |> response(200)
    assert auth_document =~ "POST #{GesttaltWeb.Endpoint.url()}/agent/identity"
    assert auth_document =~ "POST #{GesttaltWeb.Endpoint.url()}/agent/identity/claim"
    assert auth_document =~ "complete agent management server"

    user = AccountsFixtures.user_fixture()
    {:ok, _site} = Sites.ensure_site_for_user(user)
    registration = register_and_claim(conn, user)

    unsupported =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{registration["access_token"]}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", "1900-01-01")
      |> post(~p"/mcp", JSON.encode!(%{jsonrpc: "2.0", id: 1, method: "tools/list"}))

    assert json_response(unsupported, 400)["error"]["code"] == -32_600
  end

  test "renews the user-code ceremony without restarting registration", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    registration = register_agent(conn, user.email)
    original_path = verification_path(registration)

    renewed =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/agent/identity/claim",
        JSON.encode!(%{claim_token: registration["claim_token"], email: user.email})
      )
      |> json_response(200)

    assert renewed["registration_id"] == registration["registration_id"]
    assert renewed["status"] == "initiated"
    assert renewed["claim_attempt_id"] =~ "cla_"
    assert renewed["claim_attempt"]["user_code"] != registration["claim"]["user_code"]

    old_claim = conn |> recycle() |> log_in_user(user) |> get(original_path)
    assert html_response(old_claim, 404) =~ "invalid or has expired"

    renewed_uri = URI.parse(renewed["claim_attempt"]["verification_uri"])
    renewed_path = renewed_uri.path <> "?" <> renewed_uri.query

    confirmation =
      conn
      |> recycle()
      |> log_in_user(user)
      |> post(~p"/agent/identity/claim/confirm", %{
        "claim_attempt_token" => query_value(renewed_path, "claim_attempt_token"),
        "user_code" => renewed["claim_attempt"]["user_code"]
      })

    assert html_response(confirmation, 200) =~ "Access confirmed"

    token_response =
      conn
      |> recycle()
      |> post(~p"/oauth2/token", %{
        "grant_type" => @claim_grant,
        "claim_token" => registration["claim_token"]
      })
      |> json_response(200)

    assert token_response["access_token"]
  end

  test "returns protocol error codes for unsupported identity methods", %{conn: conn} do
    anonymous =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/agent/identity", JSON.encode!(%{type: "anonymous"}))
      |> json_response(400)

    assert anonymous["error"] == "anonymous_not_enabled"

    identity_assertion =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/agent/identity",
        JSON.encode!(%{type: "identity_assertion", assertion: "not-a-token"})
      )
      |> json_response(400)

    assert identity_assertion["error"] == "issuer_not_enabled"
  end

  defp register_and_claim(conn, user) do
    registration = register_agent(conn, user.email)
    claim_path = verification_path(registration)

    conn
    |> recycle()
    |> log_in_user(user)
    |> post(~p"/agent/identity/claim/confirm", %{
      "claim_attempt_token" => query_value(claim_path, "claim_attempt_token"),
      "user_code" => registration["claim"]["user_code"]
    })

    conn
    |> recycle()
    |> post(~p"/oauth2/token", %{
      "grant_type" => @claim_grant,
      "claim_token" => registration["claim_token"]
    })
    |> json_response(200)
  end

  defp register_agent(conn, email) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(
      ~p"/agent/identity",
      JSON.encode!(%{type: "service_auth", login_hint: email})
    )
    |> json_response(200)
  end

  defp query_value(path, key) do
    path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!(key)
  end

  defp verification_path(registration) do
    uri = URI.parse(registration["claim"]["verification_uri"])
    uri.path <> "?" <> uri.query
  end

  defp call_tool(conn, token, id, name, arguments) do
    response =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/mcp",
        JSON.encode!(%{
          jsonrpc: "2.0",
          id: id,
          method: "tools/call",
          params: %{name: name, arguments: arguments}
        })
      )
      |> json_response(200)

    [content] = response["result"]["content"]
    JSON.decode!(content["text"])
  end
end
