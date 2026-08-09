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
  alias Gesttalt.ThemeEditing

  @scope_names ~w(content:read content:write media:write mcp)

  setup do
    Enum.each(@scope_names, fn name ->
      %Scope{}
      |> Scope.changeset(%{name: name, label: name, public: true})
      |> Repo.insert!()
    end)

    user = AccountsFixtures.user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)
    {:ok, token} = access_token(user)

    %{site: site, token: token.value, user: user}
  end

  test "describes all publishing paths in the OpenAPI document", %{conn: conn} do
    document = conn |> get(~p"/api/openapi") |> json_response(200)

    assert document["paths"]["/api/posts"]
    assert document["paths"]["/api/photos"]
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
        JSON.encode!(%{
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

  test "registers Claude as a public client from its current metadata", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/oauth2/register",
        JSON.encode!(%{
          client_name: "Claude",
          client_uri: "https://claude.ai",
          redirect_uris: ["https://claude.ai/api/mcp/auth_callback"],
          grant_types: [
            "authorization_code",
            "refresh_token",
            Gesttalt.AgentAuth.claim_grant(),
            Gesttalt.AgentAuth.jwt_bearer_grant()
          ],
          response_types: ["code"],
          token_endpoint_auth_method: "none",
          scope: Enum.join(@scope_names, " "),
          software_id: "claude-hosted"
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
    assert client.supported_grant_types == ["authorization_code", "refresh_token"]
    assert client.metadata["client_uri"] == "https://claude.ai"
    assert client.metadata["scope"] == Enum.join(@scope_names, " ")
    assert client.metadata["software_id"] == "claude-hosted"
  end

  test "returns a secret for an explicitly confidential client", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/oauth2/register",
        JSON.encode!(%{
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
      |> post(~p"/api/posts", JSON.encode!(%{title: "Free draft", body: "Not yet"}))
      |> json_response(201)

    assert write_response["title"] == "Free draft"
  end

  test "uploads and manages photography feed entries through the application interface", %{
    conn: conn,
    token: token
  } do
    upload = upload_fixture("application-photo.png", "application photo")

    created =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/api/photos", %{
        "file" => upload,
        "alt_text" => "Sunlight passing over a concrete wall",
        "caption" => "Late July.",
        "status" => "draft"
      })
      |> json_response(201)

    assert created["status"] == "draft"
    assert created["caption"] == "Late July."
    assert created["image"]["alt_text"] == "Sunlight passing over a concrete wall"
    assert created["url"] == nil

    published =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/api/photos/#{created["id"]}/publish")
      |> json_response(200)

    assert published["status"] == "published"
    assert published["url"] == "/photography#photo-#{created["id"]}"

    listed =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/photos")
      |> json_response(200)

    assert Enum.any?(listed, &(&1["id"] == created["id"]))

    delete_response =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> delete(~p"/api/photos/#{created["id"]}")

    assert response(delete_response, 204) == ""
  end

  test "exposes publishing tools through the Model Context Protocol", %{conn: conn, token: token} do
    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/mcp", JSON.encode!(%{jsonrpc: "2.0", id: 1, method: "tools/list"}))
      |> json_response(200)

    names = Enum.map(response["result"]["tools"], & &1["name"])
    assert "create_content" in names
    assert "publish_content" in names
    assert "unpublish_content" in names
    assert "delete_content" in names
    assert "list_media" in names
    assert "delete_media" in names
    assert "list_photos" in names
    assert "upload_photo" in names
    assert "publish_photo" in names
    assert "unpublish_photo" in names
    assert "delete_photo" in names
    assert "get_theme" in names
    assert "create_theme_editing_session" in names
    assert "list_theme_preview_clients" in names
    assert "navigate_theme_preview" in names
    assert "capture_theme_preview" in names
    assert "update_theme_editing_session" in names
    assert "publish_theme_editing_session" in names
    assert "discard_theme_editing_session" in names
    assert "get_publication" in names
    assert "update_publication" in names
    assert "list_domains" in names
    assert "add_custom_domain" in names
    assert "verify_custom_domain" in names
    assert "remove_custom_domain" in names
    assert "list_connected_applications" in names
    assert "create_connected_application" in names
    assert "delete_connected_application" in names
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

  test "manages dashboard publication features through tools", %{
    conn: conn,
    site: site,
    token: token
  } do
    publication = call_tool(conn, token, 1, "get_publication")
    assert publication["id"] == site.id

    updated =
      call_tool(conn, token, 2, "update_publication", %{
        name: "Agent managed publication",
        tagline: "Managed through conversation."
      })

    assert updated["name"] == "Agent managed publication"
    assert updated["tagline"] == "Managed through conversation."

    created =
      call_tool(conn, token, 3, "create_content", %{
        title: "A complete agent workflow",
        body: "Created through the tool server.",
        tags: ["agents", "publishing"],
        status: "published"
      })

    assert created["tags"] == ["agents", "publishing"]
    assert created["status"] == "published"

    unpublished = call_tool(conn, token, 4, "unpublish_content", %{id: created["id"]})
    assert unpublished["status"] == "draft"
    assert call_tool(conn, token, 5, "delete_content", %{id: created["id"]})["deleted"]
    refute Publishing.get_post(site, created["id"])

    image =
      call_tool(conn, token, 6, "upload_media", %{
        filename: "agent-image.png",
        content_base64: Base.encode64("image contents"),
        content_type: "image/png",
        alt_text: "Uploaded by an agent"
      })

    assert image["markdown"] =~ "Uploaded by an agent"
    assert Enum.any?(call_tool(conn, token, 7, "list_media"), &(&1["id"] == image["id"]))
    assert call_tool(conn, token, 8, "delete_media", %{id: image["id"]})["deleted"]

    photo =
      call_tool(conn, token, 81, "upload_photo", %{
        filename: "agent-photo.png",
        content_base64: Base.encode64("photo contents"),
        content_type: "image/png",
        alt_text: "Uploaded to the photography feed",
        caption: "From a conversation."
      })

    assert photo["status"] == "draft"
    assert photo["image"]["alt_text"] == "Uploaded to the photography feed"
    assert Enum.any?(call_tool(conn, token, 82, "list_photos"), &(&1["id"] == photo["id"]))

    published = call_tool(conn, token, 83, "publish_photo", %{id: photo["id"]})
    assert published["status"] == "published"

    unpublished = call_tool(conn, token, 84, "unpublish_photo", %{id: photo["id"]})
    assert unpublished["status"] == "draft"
    assert call_tool(conn, token, 85, "delete_photo", %{id: photo["id"]})["deleted"]

    theme = call_tool(conn, token, 9, "get_theme")
    assert theme["name"] == "Paper"
    assert theme["variables"]["colors"]["primary"]

    domain =
      call_tool(conn, token, 10, "add_custom_domain", %{hostname: "agent.example.com"})

    assert domain["setup"]["ownership_record"]["name"] == "_gesttalt.agent.example.com"
    assert Enum.any?(call_tool(conn, token, 11, "list_domains"), &(&1["id"] == domain["id"]))
    assert call_tool(conn, token, 12, "remove_custom_domain", %{id: domain["id"]})["deleted"]

    client =
      call_tool(conn, token, 13, "create_connected_application", %{
        name: "Agent-created client",
        redirect_uris: ["https://agent.example/callback"],
        confidential: true
      })

    assert client["secret"]

    assert Enum.any?(
             call_tool(conn, token, 14, "list_connected_applications"),
             &(&1["id"] == client["id"])
           )

    assert call_tool(conn, token, 15, "delete_connected_application", %{id: client["id"]})[
             "deleted"
           ]

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

  test "observes, navigates, and captures a connected theme preview", %{
    conn: conn,
    site: site,
    token: token
  } do
    created = call_tool(conn, token, 1, "create_theme_editing_session")
    session_id = created["session_id"]
    test_process = self()

    client =
      spawn(fn ->
        loop = fn loop ->
          receive do
            {:theme_preview_navigate, page} ->
              send(test_process, {:tool_navigated_preview, page})
              loop.(loop)

            {:theme_preview_capture, request_id} ->
              result =
                ThemeEditing.complete_preview_screenshot(
                  session_id,
                  "protocol-browser-client",
                  request_id,
                  %{
                    data: "browser png",
                    height: 720,
                    mime_type: "image/png",
                    width: 1_280
                  }
                )

              send(test_process, {:tool_captured_preview, result})
              loop.(loop)
          end
        end

        loop.(loop)
      end)

    on_exit(fn ->
      Process.exit(client, :kill)
      terminate_session(session_id)
    end)

    assert {:ok, _preview} =
             ThemeEditing.connect_preview(
               session_id,
               site,
               "protocol-browser-client",
               client,
               %{
                 page: %{"kind" => "home", "title" => site.name},
                 path: "/",
                 preview_path: ThemeEditing.preview_path(session_id),
                 screenshots_enabled: true,
                 viewport: %{device_pixel_ratio: 1, height: 720, width: 1_280}
               }
             )

    listed = call_tool(conn, token, 2, "list_theme_preview_clients", %{session_id: session_id})
    assert [%{"client_id" => "protocol-browser-client", "path" => "/"}] = listed["previews"]

    navigated =
      call_tool(conn, token, 3, "navigate_theme_preview", %{
        session_id: session_id,
        client_id: "protocol-browser-client",
        path: "/"
      })

    assert navigated["preview"]["path"] == "/"
    assert_receive {:tool_navigated_preview, %{"kind" => "home"}}

    response =
      call_tool_response(conn, token, 4, "capture_theme_preview", %{
        session_id: session_id,
        client_id: "protocol-browser-client"
      })

    refute response["result"]["isError"]
    assert [metadata, image] = response["result"]["content"]
    assert JSON.decode!(metadata["text"])["path"] == "/"
    assert image["type"] == "image"
    assert image["mimeType"] == "image/png"
    assert Base.decode64!(image["data"]) == "browser png"
    assert response["result"]["structuredContent"]["result"]["width"] == 1_280
    assert_receive {:tool_captured_preview, :ok}
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
    response = call_tool_response(conn, token, id, name, arguments)

    [content] = response["result"]["content"]
    refute response["result"]["isError"]
    JSON.decode!(content["text"])
  end

  defp call_tool_response(conn, token, id, name, arguments) do
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
  end

  defp terminate_session(session_id) do
    case Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session_id) do
      [{process, _value}] ->
        DynamicSupervisor.terminate_child(Gesttalt.ThemeEditing.SessionSupervisor, process)

      [] ->
        :ok
    end
  end

  defp upload_fixture(filename, contents) do
    path = Path.join(System.tmp_dir!(), "gesttalt-interface-#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{path: path, filename: filename, content_type: "image/png"}
  end
end
