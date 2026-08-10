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

defmodule GesttaltWeb.API.Schemas.Idea do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Idea",
    type: :object,
    properties: %{
      id: %OpenApiSpex.Schema{type: :integer},
      title: %OpenApiSpex.Schema{type: :string},
      notes: %OpenApiSpex.Schema{type: :string, nullable: true},
      inserted_at: %OpenApiSpex.Schema{type: :string, format: :date_time},
      updated_at: %OpenApiSpex.Schema{type: :string, format: :date_time}
    },
    required: [:id, :title, :inserted_at, :updated_at]
  })
end

defmodule GesttaltWeb.API.Schemas.IdeaParams do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "IdeaParams",
    type: :object,
    properties: %{
      title: %OpenApiSpex.Schema{type: :string},
      notes: %OpenApiSpex.Schema{type: :string}
    },
    required: [:title]
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

defmodule GesttaltWeb.API.Schemas.Photo do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Photo",
    type: :object,
    properties: %{
      id: %OpenApiSpex.Schema{type: :integer},
      caption: %OpenApiSpex.Schema{type: :string, nullable: true},
      status: %OpenApiSpex.Schema{type: :string, enum: ["draft", "published"]},
      published_at: %OpenApiSpex.Schema{type: :string, format: :date_time, nullable: true},
      inserted_at: %OpenApiSpex.Schema{type: :string, format: :date_time},
      url: %OpenApiSpex.Schema{type: :string, nullable: true},
      image: %OpenApiSpex.Schema{
        type: :object,
        properties: %{
          id: %OpenApiSpex.Schema{type: :integer},
          filename: %OpenApiSpex.Schema{type: :string},
          content_type: %OpenApiSpex.Schema{type: :string},
          byte_size: %OpenApiSpex.Schema{type: :integer},
          alt_text: %OpenApiSpex.Schema{type: :string},
          url: %OpenApiSpex.Schema{type: :string}
        },
        required: [:id, :filename, :content_type, :byte_size, :alt_text, :url]
      }
    },
    required: [:id, :status, :inserted_at, :image]
  })
end
