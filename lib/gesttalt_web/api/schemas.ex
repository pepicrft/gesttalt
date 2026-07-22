defmodule GesttaltWeb.API.Schemas.Post do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Post",
    type: :object,
    properties: %{
      id: %OpenApiSpex.Schema{type: :integer},
      title: %OpenApiSpex.Schema{type: :string},
      slug: %OpenApiSpex.Schema{type: :string},
      excerpt: %OpenApiSpex.Schema{type: :string, nullable: true},
      tags: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}},
      body: %OpenApiSpex.Schema{type: :string},
      kind: %OpenApiSpex.Schema{type: :string, enum: ["post", "page"]},
      status: %OpenApiSpex.Schema{type: :string, enum: ["draft", "published"]},
      published_at: %OpenApiSpex.Schema{type: :string, format: :date_time, nullable: true},
      url: %OpenApiSpex.Schema{type: :string, nullable: true}
    },
    required: [:id, :title, :slug, :body, :kind, :status]
  })
end

defmodule GesttaltWeb.API.Schemas.PostParams do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "PostParams",
    type: :object,
    properties: %{
      title: %OpenApiSpex.Schema{type: :string},
      slug: %OpenApiSpex.Schema{type: :string},
      excerpt: %OpenApiSpex.Schema{type: :string},
      tags: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}},
      body: %OpenApiSpex.Schema{type: :string},
      kind: %OpenApiSpex.Schema{type: :string, enum: ["post", "page"]},
      status: %OpenApiSpex.Schema{type: :string, enum: ["draft", "published"]},
      published_at: %OpenApiSpex.Schema{type: :string, format: :date_time}
    },
    required: [:title, :body]
  })
end
