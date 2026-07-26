defmodule Gesttalt.Photography.PhotoJSON do
  @moduledoc false

  alias Gesttalt.Sites

  def render(photo) do
    %{
      id: photo.id,
      caption: photo.caption,
      status: photo.status,
      published_at: photo.published_at,
      inserted_at: photo.inserted_at,
      image: %{
        id: photo.image.id,
        filename: photo.image.filename,
        content_type: photo.image.content_type,
        byte_size: photo.image.byte_size,
        alt_text: photo.image.alt_text,
        url: Sites.image_url(photo.image)
      },
      url: if(photo.status == :published, do: "/photography#photo-#{photo.id}")
    }
  end
end
