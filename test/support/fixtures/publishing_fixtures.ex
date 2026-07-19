defmodule Gesttalt.PublishingFixtures do
  @moduledoc "Test helpers for tenant-owned posts and pages."

  import Gesttalt.AccountsFixtures

  def post_fixture(attrs \\ %{}) do
    {site, attrs} = Map.pop(attrs, :site, site_fixture())

    attrs =
      Enum.into(attrs, %{
        body: "A thoughtful body.",
        excerpt: "A concise excerpt.",
        kind: :post,
        slug: "post-#{System.unique_integer([:positive])}",
        status: :draft,
        title: "A thoughtful post"
      })

    {:ok, post} = Gesttalt.Publishing.create_post(site, attrs)
    post
  end
end
