defmodule Gesttalt.MCP do
  @moduledoc "A streamable Model Context Protocol server for publishing from compatible tools."

  @behaviour Plug

  import Plug.Conn

  alias Gesttalt.Plans
  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.PostJSON
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing
  alias Gesttalt.Themes.Variables

  @protocol_version "2025-06-18"
  @supported_protocol_versions ["2025-06-18", "2025-03-26"]
  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = GesttaltWeb.OAuthAuth.call(conn, scopes: ["mcp"])

    if conn.halted do
      conn
    else
      case requested_protocol_version(conn) do
        {:ok, _version} -> dispatch_method(conn)
        {:error, version} -> unsupported_protocol_version(conn, version)
      end
    end
  end

  defp dispatch_method(%{method: "POST"} = conn), do: dispatch(conn, conn.body_params)

  defp dispatch_method(%{method: "GET"} = conn) do
    conn
    |> put_resp_header("allow", "POST, DELETE")
    |> send_resp(405, "")
  end

  defp dispatch_method(%{method: "DELETE"} = conn), do: send_resp(conn, 204, "")

  defp dispatch_method(conn) do
    conn
    |> put_resp_header("allow", "POST, DELETE")
    |> send_resp(405, "")
  end

  defp dispatch(conn, %{"method" => "initialize", "id" => id} = request) do
    requested_version = get_in(request, ["params", "protocolVersion"])

    version =
      if requested_version in @supported_protocol_versions,
        do: requested_version,
        else: @protocol_version

    conn
    |> put_resp_header("mcp-session-id", session_id())
    |> result(id, %{
      protocolVersion: version,
      capabilities: %{tools: %{listChanged: false}},
      serverInfo: %{name: "gesttalt", title: "Gesttalt publishing", version: "1.0.0"},
      instructions:
        "For theme work, create an editing session first. Prefer the standard variables for visual design changes, preserve the stylesheet when possible, and edit Liquid only for route-specific document structure. Never publish unless the user explicitly asks."
    })
  end

  defp dispatch(conn, %{"method" => "tools/list", "id" => id}),
    do: result(conn, id, %{tools: tools()})

  defp dispatch(conn, %{
         "method" => "tools/call",
         "id" => id,
         "params" => %{"name" => name} = params
       }) do
    case call_tool(name, params["arguments"] || %{}, conn.assigns.current_site) do
      {:ok, value} ->
        result(conn, id, %{
          content: [%{type: "text", text: Jason.encode!(value)}],
          structuredContent: %{result: value}
        })

      {:error, reason} ->
        result(conn, id, %{content: [%{type: "text", text: inspect(reason)}], isError: true})
    end
  end

  defp dispatch(conn, %{"method" => "notifications/" <> _notification}),
    do: send_resp(conn, 202, "")

  defp dispatch(conn, %{"id" => id}), do: error(conn, id, -32_601, "Method not found")

  defp dispatch(conn, _params),
    do: send_resp(conn, 400, Jason.encode!(%{error: "invalid_request"}))

  defp call_tool("list_content", _arguments, site),
    do: {:ok, Enum.map(Publishing.list_posts(site), &PostJSON.render/1)}

  defp call_tool("get_content", %{"id" => id}, site) do
    case Publishing.get_post(site, id) do
      nil -> {:error, :not_found}
      post -> {:ok, PostJSON.render(post)}
    end
  end

  defp call_tool("create_content", arguments, site) do
    with {:ok, post} <- Publishing.create_post(site, arguments), do: {:ok, PostJSON.render(post)}
  end

  defp call_tool("update_content", %{"id" => id} = arguments, site) do
    with post when not is_nil(post) <- Publishing.get_post(site, id),
         {:ok, post} <- Publishing.update_post(post, Map.delete(arguments, "id")) do
      {:ok, PostJSON.render(post)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("publish_content", %{"id" => id}, site) do
    with post when not is_nil(post) <- Publishing.get_post(site, id),
         {:ok, post} <- Publishing.publish_post(post) do
      {:ok, PostJSON.render(post)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool(
         "upload_media",
         %{"filename" => filename, "content_base64" => encoded} = args,
         site
       ) do
    with true <- Plans.available?(site, :media_uploads),
         {:ok, content} <- Base.decode64(encoded),
         path <- Path.join(System.tmp_dir!(), "gesttalt-mcp-#{Ecto.UUID.generate()}"),
         :ok <- File.write(path, content),
         upload <- %Plug.Upload{
           path: path,
           filename: filename,
           content_type: args["content_type"]
         },
         {:ok, image} <- Sites.store_image(site, upload, args["alt_text"]) do
      File.rm(path)

      {:ok,
       %{
         id: image.id,
         filename: image.filename,
         url: Sites.image_url(image),
         alt_text: image.alt_text
       }}
    else
      false -> {:error, :subscription_required}
      error -> error
    end
  end

  defp call_tool("create_theme_editing_session", _arguments, site) do
    with {:ok, session} <- ThemeEditing.create(site),
         do: {:ok, ThemeEditing.present(session)}
  end

  defp call_tool("get_theme_editing_session", %{"session_id" => session_id}, site) do
    with {:ok, session} <- ThemeEditing.fetch(session_id, site),
         do: {:ok, ThemeEditing.present(session)}
  end

  defp call_tool("update_theme_editing_session", %{"session_id" => session_id} = arguments, site) do
    with {:ok, session} <-
           ThemeEditing.update(session_id, site, Map.delete(arguments, "session_id")),
         do: {:ok, ThemeEditing.present(session)}
  end

  defp call_tool("publish_theme_editing_session", %{"session_id" => session_id}, site) do
    with {:ok, theme} <- ThemeEditing.publish(session_id, site) do
      {:ok,
       %{
         session_id: session_id,
         published: true,
         theme: ThemeEditing.theme_attrs(theme)
       }}
    end
  end

  defp call_tool("discard_theme_editing_session", %{"session_id" => session_id}, site) do
    with :ok <- ThemeEditing.discard(session_id, site),
         do: {:ok, %{session_id: session_id, discarded: true}}
  end

  defp call_tool(_name, _arguments, _site), do: {:error, :unknown_tool}

  defp tools do
    [
      tool("list_content", "List every post and page for the authenticated publication", %{}),
      tool("get_content", "Get one post or page", %{id: integer_schema()}),
      tool(
        "create_content",
        "Create a draft or published post or page",
        content_schema(["title", "body"])
      ),
      tool(
        "update_content",
        "Update a post or page",
        Map.put(
          content_schema([]),
          :properties,
          Map.put(content_schema([]).properties, :id, integer_schema())
        )
        |> Map.put(:required, ["id"])
      ),
      tool("publish_content", "Publish a post or page", %{id: integer_schema()}),
      tool("upload_media", "Upload an image for use in published content on a paid plan", %{
        filename: string_schema(),
        content_base64: string_schema(),
        content_type: string_schema(),
        alt_text: string_schema()
      }),
      tool(
        "create_theme_editing_session",
        "Create one of up to five isolated drafts from the active theme and return its live preview address, standard variables, and variable contract",
        %{properties: %{}, required: []}
      ),
      tool(
        "get_theme_editing_session",
        "Get the current theme draft, preview address, and revision",
        session_schema()
      ),
      tool(
        "update_theme_editing_session",
        "Apply partial standard-variable, stylesheet, or Liquid route-template changes to a theme draft and reload its open preview",
        %{
          properties: Map.put(theme_properties(), :session_id, string_schema()),
          required: ["session_id"]
        }
      ),
      tool(
        "publish_theme_editing_session",
        "Publish a completed theme draft and close its editing session",
        session_schema()
      ),
      tool(
        "discard_theme_editing_session",
        "Discard a theme draft without changing the active theme",
        session_schema()
      )
    ]
  end

  defp tool(name, description, schema) do
    properties = Map.get(schema, :properties, schema)
    required = Map.get(schema, :required, Map.keys(properties) |> Enum.map(&to_string/1))

    %{
      name: name,
      title: tool_title(name),
      description: description,
      inputSchema: %{
        type: "object",
        properties: properties,
        required: required,
        additionalProperties: false
      },
      outputSchema: %{
        type: "object",
        properties: %{result: %{}},
        required: ["result"]
      },
      annotations: tool_annotations(name)
    }
  end

  defp tool_title(name),
    do: name |> String.replace("_", " ") |> String.capitalize()

  defp tool_annotations(name) do
    read_only = name in ["list_content", "get_content", "get_theme_editing_session"]

    %{
      title: tool_title(name),
      readOnlyHint: read_only,
      destructiveHint: name in ["publish_theme_editing_session", "discard_theme_editing_session"],
      idempotentHint: read_only,
      openWorldHint: false
    }
  end

  defp content_schema(required),
    do: %{
      properties: %{
        title: string_schema(),
        slug: string_schema(),
        excerpt: string_schema(),
        body: string_schema(),
        kind: %{type: "string", enum: ["post", "page"]},
        status: %{type: "string", enum: ["draft", "published"]}
      },
      required: required
    }

  defp session_schema, do: %{properties: %{session_id: string_schema()}, required: ["session_id"]}

  defp theme_properties,
    do: %{
      name: string_schema(),
      index_template: string_schema(),
      article_template: string_schema(),
      page_template: string_schema(),
      stylesheet: string_schema(),
      variables: Variables.input_schema()
    }

  defp string_schema, do: %{type: "string"}
  defp integer_schema, do: %{type: "integer"}

  defp result(conn, id, value), do: respond(conn, %{jsonrpc: "2.0", id: id, result: value})

  defp error(conn, id, code, message),
    do: respond(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})

  defp respond(conn, body),
    do: conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))

  defp requested_protocol_version(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] -> {:ok, nil}
      [version] when version in @supported_protocol_versions -> {:ok, version}
      [version] -> {:error, version}
      _versions -> {:error, "multiple values"}
    end
  end

  defp unsupported_protocol_version(conn, version) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      400,
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: nil,
        error: %{
          code: -32_600,
          message:
            "Unsupported Model Context Protocol version #{version}. Supported versions: #{Enum.join(@supported_protocol_versions, ", ")}."
        }
      })
    )
  end

  defp session_id,
    do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
