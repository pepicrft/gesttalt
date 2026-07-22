defmodule GesttaltWeb.PublishingInterfacesTest do
  # The authorization scope names are globally unique rows shared with another integration suite.
  use GesttaltWeb.ConnCase, async: false

  alias Boruta.Ecto.AccessTokens
  alias Boruta.Ecto.Admin.Clients
  alias Boruta.Ecto.Client
  alias Boruta.Ecto.OauthMapper
  alias Boruta.Ecto.Scope
  alias Gesttalt.AccountsFixtures
  alias Gesttalt.OAuth.ResourceOwners
  alias Gesttalt.Publishing
  alias Gesttalt.Repo
  alias Gesttalt.Sites

  @scope_names ~w(content:read content:write media:write mcp)

  setup do
    Enum.each(@scope_names, fn name ->
      %Scope{}
      |> Scope.changeset(%{name: name, label: name, public: true})
      |> Repo.insert!()
    end)

    user = AccountsFixtures.user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)
    {:ok, site} = Sites.update_billing(site, %{subscription_status: :trialing})
    {:ok, token} = access_token(user)

    %{site: site, token: token.value, user: user}
  end

  test "describes all publishing paths in the OpenAPI document", %{conn: conn} do
    document = conn |> get(~p"/api/openapi") |> json_response(200)

    assert document["paths"]["/api/posts"]
    refute document["paths"]["/api/theme"]
    assert document["paths"]["/api/media"]
    assert document["components"]["securitySchemes"]["oauth2"]
  end

  test "registers a public mobile client dynamically", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/oauth2/register",
        Jason.encode!(%{
          client_name: "Mobile writer",
          redirect_uris: ["gesttalt-mobile://oauth/callback"],
          grant_types: ["authorization_code", "refresh_token"],
          token_endpoint_auth_method: "none"
        })
      )

    response = json_response(conn, 201)
    assert response["client_id"]
    assert response["client_name"] == "Mobile writer"
    assert response["token_endpoint_auth_method"] == "none"
  end

  test "registers Claude as a public client from its minimal metadata", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/oauth2/register",
        Jason.encode!(%{
          client_name: "Claude",
          redirect_uris: ["https://claude.ai/api/mcp/auth_callback"]
        })
      )

    response = json_response(conn, 201)

    assert response["client_id"]
    assert response["client_name"] == "Claude"
    assert response["redirect_uris"] == ["https://claude.ai/api/mcp/auth_callback"]
    assert response["grant_types"] == ["authorization_code", "refresh_token"]
    assert response["response_types"] == ["code"]
    assert response["token_endpoint_auth_method"] == "none"
    refute response["client_secret"]
    refute response["client_secret_expires_at"]

    client = Repo.get!(Client, response["client_id"])
    refute client.confidential
    assert client.pkce
    assert client.public_refresh_token
  end

  test "returns a secret for an explicitly confidential client", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/oauth2/register",
        Jason.encode!(%{
          client_name: "Confidential writer",
          redirect_uris: ["https://writer.example/oauth/callback"],
          grant_types: ["authorization_code", "refresh_token"],
          token_endpoint_auth_method: "client_secret_basic"
        })
      )

    response = json_response(conn, 201)

    assert response["client_secret"]
    assert response["client_secret_expires_at"] == 0
    assert response["token_endpoint_auth_method"] == "client_secret_basic"

    client = Repo.get!(Client, response["client_id"])
    assert client.confidential
  end

  test "uses one tenant-scoped token for the application interface", %{
    conn: conn,
    site: site,
    token: token
  } do
    {:ok, _post} =
      Publishing.create_post(site, %{title: "From anywhere", body: "A programmable post."})

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/posts")
      |> json_response(200)

    assert [%{"title" => "From anywhere"}] = response
  end

  test "keeps programmatic text publishing free", %{
    conn: conn,
    site: site,
    token: token
  } do
    {:ok, _site} = Sites.update_billing(site, %{subscription_status: :inactive})

    read_response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/posts")
      |> json_response(200)

    assert read_response == []

    write_response =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/posts", Jason.encode!(%{title: "Free draft", body: "Not yet"}))
      |> json_response(201)

    assert write_response["title"] == "Free draft"
  end

  test "exposes publishing tools through the Model Context Protocol", %{conn: conn, token: token} do
    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "tools/list"}))
      |> json_response(200)

    names = Enum.map(response["result"]["tools"], & &1["name"])
    assert "create_content" in names
    assert "publish_content" in names
    assert "create_theme_editing_session" in names
    assert "update_theme_editing_session" in names
    assert "publish_theme_editing_session" in names
    assert "discard_theme_editing_session" in names
    refute "publish_theme" in names

    update_tool =
      Enum.find(response["result"]["tools"], &(&1["name"] == "update_theme_editing_session"))

    assert update_tool["inputSchema"]["properties"]["variables"]["properties"]["colors"]
    assert update_tool["inputSchema"]["properties"]["variables"]["properties"]["fontSizes"]
    refute update_tool["inputSchema"]["additionalProperties"]

    publish_tool =
      Enum.find(response["result"]["tools"], &(&1["name"] == "publish_theme_editing_session"))

    assert publish_tool["annotations"]["destructiveHint"]
  end

  test "supports the streamable transport lifecycle used by agents", %{conn: conn, token: token} do
    get_conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/mcp")

    assert response(get_conn, 405) == ""
    assert get_resp_header(get_conn, "allow") == ["POST, DELETE"]

    delete_conn =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> delete(~p"/mcp")

    assert response(delete_conn, 204) == ""
  end

  test "edits, previews, and publishes a theme through one session", %{
    conn: conn,
    site: site,
    token: token
  } do
    original_stylesheet = Sites.get_theme!(site).stylesheet

    created = call_tool(conn, token, 1, "create_theme_editing_session")
    session_id = created["session_id"]

    assert is_binary(session_id)
    assert created["preview_url"] =~ "/theme-previews/#{session_id}"
    assert created["revision"] == 0
    assert created["theme"]["variables"]["colors"]["primary"]
    assert created["variable_contract"]["reference"]["url"] == "https://theme-ui.com/theme-spec"

    updated =
      call_tool(conn, token, 2, "update_theme_editing_session", %{
        session_id: session_id,
        stylesheet: "body { background: papayawhip; }",
        variables: %{colors: %{primary: "#d73a49"}}
      })

    assert updated["revision"] == 1
    assert updated["theme"]["stylesheet"] == "body { background: papayawhip; }"
    assert updated["theme"]["variables"]["colors"]["primary"] == "#d73a49"
    assert updated["theme"]["variables"]["colors"]["background"] == "#fdfbf7"
    assert Sites.get_theme!(site).stylesheet == original_stylesheet

    preview_path = URI.parse(updated["preview_url"]).path
    preview = conn |> recycle() |> get(preview_path) |> html_response(200)
    assert preview =~ "body { background: papayawhip; }"

    published =
      call_tool(conn, token, 3, "publish_theme_editing_session", %{session_id: session_id})

    assert published["published"]
    assert Sites.get_theme!(site).stylesheet == "body { background: papayawhip; }"
    assert Sites.get_theme!(site).variables["colors"]["primary"] == "#d73a49"

    preview_conn = conn |> recycle() |> get(preview_path)
    assert response(preview_conn, 404) =~ "not found or expired"
  end

  test "advertises protected-resource metadata when a token is missing", %{conn: conn} do
    conn = get(conn, ~p"/api/posts")

    assert %{"error" => "invalid_token"} = json_response(conn, 401)
    assert [challenge] = get_resp_header(conn, "www-authenticate")
    assert challenge =~ "/.well-known/oauth-protected-resource"
  end

  defp access_token(user) do
    {:ok, client_schema} =
      Clients.create_client(%{
        name: "Test client",
        redirect_uris: ["https://client.example/callback"],
        supported_grant_types: ["authorization_code", "refresh_token", "revoke"],
        token_endpoint_auth_methods: ["client_secret_basic"],
        confidential: true,
        pkce: true,
        authorized_scopes: Enum.map(@scope_names, &%{name: &1})
      })

    client = OauthMapper.to_oauth_schema(client_schema)
    {:ok, owner} = ResourceOwners.get_by(sub: to_string(user.id))

    AccessTokens.create(
      %{
        client: client,
        scope: Enum.join(@scope_names, " "),
        sub: to_string(user.id),
        resource_owner: owner
      },
      refresh_token: false
    )
  end

  defp call_tool(conn, token, id, name, arguments \\ %{}) do
    response =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/mcp",
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: id,
          method: "tools/call",
          params: %{name: name, arguments: arguments}
        })
      )
      |> json_response(200)

    [content] = response["result"]["content"]
    refute response["result"]["isError"]
    Jason.decode!(content["text"])
  end
end
