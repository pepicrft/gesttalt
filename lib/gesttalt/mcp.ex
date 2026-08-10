defmodule Gesttalt.MCP do
  @moduledoc "A streamable Model Context Protocol server for publishing from compatible tools."

  @behaviour Plug

  import Plug.Conn

  alias Gesttalt.OAuth.ClientsManager
  alias Gesttalt.Photography
  alias Gesttalt.Photography.PhotoJSON
  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.IdeaJSON
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

  defp instructions do
    "This server can manage every publication feature exposed by the dashboard. Inspect the current state before changing it. For theme work, create an editing session first. Prefer the standard variables for visual design changes, preserve the stylesheet when possible, and edit Liquid only for route-specific document structure. Never publish, unpublish, delete, change domains, or create credentials unless the user explicitly asks."
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
      instructions: instructions()
    })
  end

  defp dispatch(conn, %{"method" => "tools/list", "id" => id}),
    do: result(conn, id, %{tools: tools()})

  defp dispatch(conn, %{
         "method" => "tools/call",
         "id" => id,
         "params" => %{"name" => name} = params
       }) do
    case call_tool(
           name,
           params["arguments"] || %{},
           conn.assigns.current_site,
           conn.assigns.current_user
         ) do
      {:ok, value, additional_content} ->
        result(conn, id, %{
          content: [%{type: "text", text: JSON.encode!(value)} | additional_content],
          structuredContent: %{result: value}
        })

      {:ok, value} ->
        result(conn, id, %{
          content: [%{type: "text", text: JSON.encode!(value)}],
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
    do: send_resp(conn, 400, JSON.encode!(%{error: "invalid_request"}))

  defp call_tool("list_content", _arguments, site, _user),
    do: {:ok, Enum.map(Publishing.list_posts(site), &PostJSON.render/1)}

  defp call_tool("get_content", %{"id" => id}, site, _user) do
    case Publishing.get_post(site, id) do
      nil -> {:error, :not_found}
      post -> {:ok, PostJSON.render(post)}
    end
  end

  defp call_tool("create_content", arguments, site, _user) do
    with {:ok, post} <- Publishing.create_post(site, arguments), do: {:ok, PostJSON.render(post)}
  end

  defp call_tool("update_content", %{"id" => id} = arguments, site, _user) do
    with post when not is_nil(post) <- Publishing.get_post(site, id),
         {:ok, post} <- Publishing.update_post(post, Map.delete(arguments, "id")) do
      {:ok, PostJSON.render(post)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("publish_content", %{"id" => id}, site, _user) do
    with post when not is_nil(post) <- Publishing.get_post(site, id),
         {:ok, post} <- Publishing.publish_post(post) do
      {:ok, PostJSON.render(post)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("unpublish_content", %{"id" => id}, site, _user) do
    with post when not is_nil(post) <- Publishing.get_post(site, id),
         {:ok, post} <- Publishing.unpublish_post(post) do
      {:ok, PostJSON.render(post)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("delete_content", %{"id" => id}, site, _user) do
    with post when not is_nil(post) <- Publishing.get_post(site, id),
         {:ok, post} <- Publishing.delete_post(post) do
      {:ok, %{id: post.id, deleted: true}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("list_ideas", _arguments, site, _user),
    do: {:ok, Enum.map(Publishing.list_ideas(site), &IdeaJSON.render/1)}

  defp call_tool("get_idea", %{"id" => id}, site, _user) do
    case Publishing.get_idea(site, id) do
      nil -> {:error, :not_found}
      idea -> {:ok, IdeaJSON.render(idea)}
    end
  end

  defp call_tool("create_idea", arguments, site, _user) do
    with {:ok, idea} <- Publishing.create_idea(site, arguments), do: {:ok, IdeaJSON.render(idea)}
  end

  defp call_tool("update_idea", %{"id" => id} = arguments, site, _user) do
    with idea when not is_nil(idea) <- Publishing.get_idea(site, id),
         {:ok, idea} <- Publishing.update_idea(idea, Map.delete(arguments, "id")) do
      {:ok, IdeaJSON.render(idea)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("delete_idea", %{"id" => id}, site, _user) do
    with idea when not is_nil(idea) <- Publishing.get_idea(site, id),
         {:ok, idea} <- Publishing.delete_idea(idea) do
      {:ok, %{id: idea.id, deleted: true}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("list_media", _arguments, site, _user),
    do: {:ok, Enum.map(Sites.list_images(site), &present_image/1)}

  defp call_tool(
         "upload_media",
         %{"filename" => filename, "content_base64" => encoded} = args,
         site,
         _user
       ) do
    with {:ok, content} <- Base.decode64(encoded),
         path <- Path.join(System.tmp_dir!(), "gesttalt-mcp-#{Ecto.UUID.generate()}"),
         :ok <- File.write(path, content) do
      try do
        upload = %Plug.Upload{
          path: path,
          filename: filename,
          content_type: args["content_type"]
        }

        with {:ok, image} <- Sites.store_image(site, upload, args["alt_text"]),
             do: {:ok, present_image(image)}
      after
        File.rm(path)
      end
    else
      :error -> {:error, :invalid_base64}
      error -> error
    end
  end

  defp call_tool("delete_media", %{"id" => id}, site, _user) do
    case Enum.find(Sites.list_images(site), &(&1.id == id)) do
      nil ->
        {:error, :not_found}

      image ->
        with {:ok, image} <- Sites.delete_image(site, image.id),
             do: {:ok, %{id: image.id, filename: image.filename, deleted: true}}
    end
  end

  defp call_tool("list_photos", _arguments, site, _user),
    do: {:ok, Enum.map(Photography.list_photos(site), &PhotoJSON.render/1)}

  defp call_tool(
         "upload_photo",
         %{"filename" => filename, "content_base64" => encoded, "alt_text" => _alt_text} = args,
         site,
         _user
       ) do
    with {:ok, content} <- Base.decode64(encoded),
         path <- Path.join(System.tmp_dir!(), "gesttalt-mcp-photo-#{Ecto.UUID.generate()}"),
         :ok <- File.write(path, content) do
      try do
        upload = %Plug.Upload{
          path: path,
          filename: filename,
          content_type: args["content_type"]
        }

        attrs = Map.put_new(args, "status", "draft")

        with {:ok, photo} <- Photography.create_photo(site, upload, attrs),
             do: {:ok, PhotoJSON.render(photo)}
      after
        File.rm(path)
      end
    else
      :error -> {:error, :invalid_base64}
      error -> error
    end
  end

  defp call_tool("publish_photo", %{"id" => id}, site, _user) do
    with photo when not is_nil(photo) <- Photography.get_photo(site, id),
         {:ok, photo} <- Photography.publish_photo(photo) do
      {:ok, PhotoJSON.render(photo)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("unpublish_photo", %{"id" => id}, site, _user) do
    with photo when not is_nil(photo) <- Photography.get_photo(site, id),
         {:ok, photo} <- Photography.unpublish_photo(photo) do
      {:ok, PhotoJSON.render(photo)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp call_tool("delete_photo", %{"id" => id}, site, _user) do
    case Photography.get_photo(site, id) do
      nil ->
        {:error, :not_found}

      photo ->
        with {:ok, photo} <- Photography.delete_photo(site, photo.id),
             do: {:ok, %{id: photo.id, deleted: true}}
    end
  end

  defp call_tool("get_theme", _arguments, site, _user),
    do: {:ok, site |> Sites.get_theme!() |> ThemeEditing.theme_attrs()}

  defp call_tool("create_theme_editing_session", _arguments, site, _user) do
    with {:ok, session} <- ThemeEditing.create(site),
         do: {:ok, ThemeEditing.present(session)}
  end

  defp call_tool("get_theme_editing_session", %{"session_id" => session_id}, site, _user) do
    with {:ok, session} <- ThemeEditing.fetch(session_id, site),
         do: {:ok, ThemeEditing.present(session)}
  end

  defp call_tool("list_theme_preview_clients", %{"session_id" => session_id}, site, _user) do
    with {:ok, previews} <- ThemeEditing.list_previews(session_id, site),
         do: {:ok, %{session_id: session_id, previews: previews}}
  end

  defp call_tool(
         "navigate_theme_preview",
         %{"path" => path, "session_id" => session_id} = arguments,
         site,
         _user
       ) do
    with {:ok, preview} <-
           ThemeEditing.navigate_preview(session_id, site, arguments["client_id"], path),
         do: {:ok, %{preview: preview, session_id: session_id}}
  end

  defp call_tool(
         "capture_theme_preview",
         %{"session_id" => session_id} = arguments,
         site,
         _user
       ) do
    with {:ok, screenshot} <-
           ThemeEditing.capture_preview(session_id, site, arguments["client_id"]) do
      {data, screenshot} = Map.pop!(screenshot, :data)
      screenshot = Map.update!(screenshot, :captured_at, &DateTime.to_iso8601/1)

      {:ok, screenshot,
       [
         %{
           type: "image",
           data: Base.encode64(data),
           mimeType: screenshot.mime_type
         }
       ]}
    end
  end

  defp call_tool(
         "update_theme_editing_session",
         %{"session_id" => session_id} = arguments,
         site,
         _user
       ) do
    with {:ok, session} <-
           ThemeEditing.update(session_id, site, Map.delete(arguments, "session_id")),
         do: {:ok, ThemeEditing.present(session)}
  end

  defp call_tool(
         "publish_theme_editing_session",
         %{"session_id" => session_id},
         site,
         _user
       ) do
    with {:ok, theme} <- ThemeEditing.publish(session_id, site) do
      {:ok,
       %{
         session_id: session_id,
         published: true,
         theme: ThemeEditing.theme_attrs(theme)
       }}
    end
  end

  defp call_tool(
         "discard_theme_editing_session",
         %{"session_id" => session_id},
         site,
         _user
       ) do
    with :ok <- ThemeEditing.discard(session_id, site),
         do: {:ok, %{session_id: session_id, discarded: true}}
  end

  defp call_tool("get_publication", _arguments, site, _user),
    do: {:ok, present_publication(site)}

  defp call_tool("update_publication", arguments, site, _user) do
    with {:ok, site} <- Sites.update_site(site, arguments),
         do: {:ok, present_publication(site)}
  end

  defp call_tool("list_domains", _arguments, site, _user),
    do: {:ok, Enum.map(Sites.list_domains(site), &present_domain/1)}

  defp call_tool("add_custom_domain", %{"hostname" => hostname}, site, _user) do
    with {:ok, domain} <- Sites.add_custom_domain(site, %{hostname: hostname}) do
      {:ok, present_domain(domain)}
    end
  end

  defp call_tool("verify_custom_domain", %{"id" => id}, site, _user) do
    case Enum.find(Sites.list_domains(site), &(&1.id == id and &1.kind == :custom)) do
      nil ->
        {:error, :not_found}

      domain ->
        with {:ok, domain} <- Sites.verify_domain(site, domain.id),
             do: {:ok, present_domain(domain)}
    end
  end

  defp call_tool("remove_custom_domain", %{"id" => id}, site, _user) do
    with {:ok, domain} <- Sites.delete_domain(site, id),
         do: {:ok, %{id: domain.id, hostname: domain.hostname, deleted: true}}
  end

  defp call_tool("list_connected_applications", _arguments, _site, user),
    do: {:ok, Enum.map(ClientsManager.list_clients(user), &present_client/1)}

  defp call_tool("create_connected_application", arguments, _site, user) do
    with {:ok, client} <- ClientsManager.create_client(user, arguments),
         do: {:ok, present_client(client, include_secret: true)}
  end

  defp call_tool("delete_connected_application", %{"id" => id}, _site, user) do
    with {:ok, client} <- ClientsManager.delete_client(user, id),
         do: {:ok, %{id: client.id, name: client.name, deleted: true}}
  end

  defp call_tool(_name, _arguments, _site, _user), do: {:error, :unknown_tool}

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
      tool("unpublish_content", "Move a published post or page back to drafts", %{
        id: integer_schema()
      }),
      tool("delete_content", "Permanently delete a post or page", %{id: integer_schema()}),
      tool("list_ideas", "List conversation ideas for the authenticated publication", %{}),
      tool("get_idea", "Get one conversation idea", %{id: integer_schema()}),
      tool("create_idea", "Create a conversation idea", idea_schema(["title"])),
      tool(
        "update_idea",
        "Update a conversation idea",
        Map.put(
          idea_schema([]),
          :properties,
          Map.put(idea_schema([]).properties, :id, integer_schema())
        )
        |> Map.put(:required, ["id"])
      ),
      tool("delete_idea", "Permanently delete a conversation idea", %{id: integer_schema()}),
      tool("list_media", "List every image in the publication media library", %{}),
      tool(
        "upload_media",
        "Upload an image for use in published content",
        %{
          properties: %{
            filename: string_schema(),
            content_base64: string_schema(),
            content_type: string_schema(),
            alt_text: string_schema()
          },
          required: ["filename", "content_base64"]
        }
      ),
      tool("delete_media", "Permanently delete an image from the media library", %{
        id: integer_schema()
      }),
      tool("list_photos", "List every draft and published photography feed entry", %{}),
      tool(
        "upload_photo",
        "Upload a photograph as a draft or publish it to the photography feed",
        %{
          properties: %{
            filename: string_schema(),
            content_base64: string_schema(),
            content_type: string_schema(),
            alt_text: string_schema(),
            caption: string_schema(),
            status: %{type: "string", enum: ["draft", "published"]}
          },
          required: ["filename", "content_base64", "alt_text"]
        }
      ),
      tool("publish_photo", "Publish a photography feed entry", %{id: integer_schema()}),
      tool("unpublish_photo", "Move a published photography feed entry back to drafts", %{
        id: integer_schema()
      }),
      tool("delete_photo", "Permanently delete a photography feed entry and its image", %{
        id: integer_schema()
      }),
      tool("get_theme", "Get the active publication theme", %{}),
      tool(
        "create_theme_editing_session",
        "Create one of up to five durable, isolated drafts from the active theme and return its live preview address, standard variables, and variable contract. Draft revisions survive application deployments",
        %{properties: %{}, required: []}
      ),
      tool(
        "get_theme_editing_session",
        "Get the current theme draft, preview address, revision, and connected browser previews",
        session_schema()
      ),
      tool(
        "list_theme_preview_clients",
        "List connected browser previews with their current page, viewport, and screenshot permission",
        session_schema()
      ),
      tool(
        "navigate_theme_preview",
        "Navigate one connected browser preview to a public path such as /, /blog/my-post, or /about. The client identifier is optional when exactly one preview is connected",
        %{
          properties: %{
            session_id: string_schema(),
            client_id: string_schema(),
            path: string_schema()
          },
          required: ["session_id", "path"]
        }
      ),
      tool(
        "capture_theme_preview",
        "Capture the current connected browser preview after the user has enabled screenshot access. The client identifier is optional when exactly one preview is connected",
        %{
          properties: %{session_id: string_schema(), client_id: string_schema()},
          required: ["session_id"]
        }
      ),
      tool(
        "update_theme_editing_session",
        "Apply partial standard-variable, stylesheet, or Liquid route-template changes to a theme draft and refresh its open preview",
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
      ),
      tool("get_publication", "Get publication identity, plan, and address settings", %{}),
      tool(
        "update_publication",
        "Update the publication name, tagline, or homepage description written in Markdown",
        %{
          properties: %{
            name: string_schema(),
            tagline: string_schema(),
            description: string_schema()
          },
          required: []
        }
      ),
      tool("list_domains", "List platform and custom domains with setup instructions", %{}),
      tool("add_custom_domain", "Add a custom domain", %{
        hostname: string_schema()
      }),
      tool(
        "verify_custom_domain",
        "Check the ownership and routing records for a custom domain",
        %{
          id: integer_schema()
        }
      ),
      tool("remove_custom_domain", "Remove a custom domain", %{id: integer_schema()}),
      tool(
        "list_connected_applications",
        "List authorization clients created by the publication owner",
        %{}
      ),
      tool(
        "create_connected_application",
        "Create an authorization client and return its secret once",
        %{
          properties: %{
            name: string_schema(),
            redirect_uris: %{type: "array", items: string_schema(), minItems: 1},
            confidential: boolean_schema()
          },
          required: ["name", "redirect_uris"]
        }
      ),
      tool("delete_connected_application", "Delete an authorization client", %{
        id: string_schema()
      })
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
    read_only =
      name in [
        "list_content",
        "get_content",
        "list_ideas",
        "get_idea",
        "list_media",
        "list_photos",
        "get_theme",
        "get_theme_editing_session",
        "list_theme_preview_clients",
        "capture_theme_preview",
        "get_publication",
        "list_domains",
        "list_connected_applications"
      ]

    destructive =
      name in [
        "delete_content",
        "delete_idea",
        "delete_media",
        "delete_photo",
        "publish_theme_editing_session",
        "discard_theme_editing_session",
        "remove_custom_domain",
        "delete_connected_application"
      ]

    open_world = name == "verify_custom_domain"

    %{
      title: tool_title(name),
      readOnlyHint: read_only,
      destructiveHint: destructive,
      idempotentHint: read_only and name != "capture_theme_preview",
      openWorldHint: open_world
    }
  end

  defp content_schema(required),
    do: %{
      properties: %{
        title: string_schema(),
        slug: string_schema(),
        excerpt: string_schema(),
        tags: %{type: "array", items: string_schema()},
        body: string_schema(),
        kind: %{type: "string", enum: ["post", "page"]},
        status: %{type: "string", enum: ["draft", "published"]},
        published_at: %{type: "string", format: "date-time"}
      },
      required: required
    }

  defp idea_schema(required),
    do: %{
      properties: %{title: string_schema(), notes: string_schema()},
      required: required
    }

  defp session_schema, do: %{properties: %{session_id: string_schema()}, required: ["session_id"]}

  defp theme_properties,
    do: %{
      name: string_schema(),
      index_template: string_schema(),
      article_template: string_schema(),
      page_template: string_schema(),
      photography_template: string_schema(),
      stylesheet: string_schema(),
      variables: Variables.input_schema()
    }

  defp string_schema, do: %{type: "string"}
  defp integer_schema, do: %{type: "integer"}
  defp boolean_schema, do: %{type: "boolean"}

  defp present_image(image),
    do: %{
      id: image.id,
      filename: image.filename,
      content_type: image.content_type,
      byte_size: image.byte_size,
      alt_text: image.alt_text,
      url: Sites.image_url(image),
      markdown: "![#{image.alt_text || ""}](#{Sites.image_url(image)})"
    }

  defp present_publication(site),
    do: %{
      id: site.id,
      name: site.name,
      handle: site.handle,
      tagline: site.tagline,
      description: site.description,
      domains: Enum.map(Sites.list_domains(site), &present_domain/1)
    }

  defp present_domain(domain) do
    setup =
      if domain.kind == :custom and domain.status == :pending do
        %{
          ownership_record: %{
            type: "TXT",
            name: "_gesttalt.#{domain.hostname}",
            value: "gesttalt-domain=#{domain.verification_token}"
          },
          routing_record: %{
            type: "CNAME",
            name: domain.hostname,
            value: Sites.custom_domain_target()
          }
        }
      end

    %{
      id: domain.id,
      hostname: domain.hostname,
      kind: domain.kind,
      status: domain.status,
      verified_at: domain.verified_at,
      setup: setup
    }
  end

  defp present_client(client, opts \\ []) do
    data = %{
      id: client.id,
      name: client.name,
      redirect_uris: client.redirect_uris,
      confidential: client.confidential,
      inserted_at: client.inserted_at
    }

    if Keyword.get(opts, :include_secret), do: Map.put(data, :secret, client.secret), else: data
  end

  defp result(conn, id, value), do: respond(conn, %{jsonrpc: "2.0", id: id, result: value})

  defp error(conn, id, code, message),
    do: respond(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})

  defp respond(conn, body),
    do: conn |> put_resp_content_type("application/json") |> send_resp(200, JSON.encode!(body))

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
      JSON.encode!(%{
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
