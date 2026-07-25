defmodule Gesttalt.OpenGraphTest do
  use Gesttalt.DataCase, async: true
  use Mimic

  alias Gesttalt.MediaStorage
  alias Gesttalt.OpenGraph

  import Gesttalt.AccountsFixtures
  import Gesttalt.PublishingFixtures

  defp published_post(site, attrs \\ %{}) do
    post = post_fixture(Map.merge(%{site: site}, attrs))
    {:ok, post} = Gesttalt.Publishing.publish_post(post)
    post
  end

  describe "render/2" do
    setup do
      %{site: site_fixture(user_fixture())}
    end

    test "renders and stores the image on a cache miss", %{site: site} do
      post = published_post(site)

      stub(MediaStorage, :get, fn _key -> {:error, :not_found} end)
      expect(Carta, :render, fn _pool, html, _opts -> {:ok, "JPEG:" <> html} end)
      expect(MediaStorage, :put, fn _key, "JPEG:" <> _rest, "image/jpeg" -> :ok end)

      assert {:ok, "JPEG:" <> _} = OpenGraph.render(site, %{"kind" => "post", "id" => post.id})
    end

    test "serves from storage without rendering on a cache hit", %{site: site} do
      post = published_post(site)

      stub(MediaStorage, :get, fn _key -> {:ok, "CACHED-BYTES"} end)
      reject(&Carta.render/3)

      assert {:ok, "CACHED-BYTES"} = OpenGraph.render(site, %{"kind" => "post", "id" => post.id})
    end

    test "renders the home card", %{site: site} do
      stub(MediaStorage, :get, fn _key -> {:error, :not_found} end)
      expect(Carta, :render, fn _pool, _html, _opts -> {:ok, "HOME-JPEG"} end)
      stub(MediaStorage, :put, fn _key, _body, _content_type -> :ok end)

      assert {:ok, "HOME-JPEG"} = OpenGraph.render(site, %{"kind" => "home"})
    end

    test "returns :not_found for an unpublished post without rendering", %{site: site} do
      draft = post_fixture(%{site: site})
      reject(&Carta.render/3)

      assert {:error, :not_found} =
               OpenGraph.render(site, %{"kind" => "post", "id" => draft.id})
    end

    test "returns :not_found for unknown or malformed identifiers", %{site: site} do
      reject(&Carta.render/3)

      assert {:error, :not_found} =
               OpenGraph.render(site, %{"kind" => "post", "id" => Ecto.UUID.generate()})

      assert {:error, :not_found} =
               OpenGraph.render(site, %{"kind" => "post", "id" => "not-a-uuid"})
    end
  end

  describe "image_url/2 and verify_signature/1" do
    setup do
      %{site: site_fixture(user_fixture())}
    end

    test "mints a signed URL that verifies", %{site: site} do
      post = published_post(site)
      ctx = %{site: site, theme: site.theme, base_url: "https://example.test"}

      url = OpenGraph.image_url({:post, post}, ctx)
      assert String.starts_with?(url, "https://example.test/og-image?")

      params = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert OpenGraph.verify_signature(params)
    end

    test "a URL with a tampered parameter fails verification", %{site: site} do
      post = published_post(site)
      ctx = %{site: site, theme: site.theme, base_url: "https://example.test"}

      params =
        {:post, post}
        |> OpenGraph.image_url(ctx)
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.decode_query()
        |> Map.put("id", Ecto.UUID.generate())

      refute OpenGraph.verify_signature(params)
    end
  end
end
