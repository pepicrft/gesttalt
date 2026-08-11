defmodule Gesttalt.OpenGraphTest do
  use Gesttalt.DataCase, async: true
  use Mimic

  alias Gesttalt.MediaStorage
  alias Gesttalt.OpenGraph
  alias Gesttalt.Sites.ThemeDefaults

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

    test "renders when local storage reports a missing file", %{site: site} do
      post = published_post(site)

      stub(MediaStorage, :get, fn _key -> {:error, :enoent} end)
      expect(Carta, :render, fn _pool, html, _opts -> {:ok, "LOCAL-JPEG:" <> html} end)
      expect(MediaStorage, :put, fn _key, "LOCAL-JPEG:" <> _rest, "image/jpeg" -> :ok end)

      assert {:ok, "LOCAL-JPEG:" <> _} =
               OpenGraph.render(site, %{"kind" => "post", "id" => post.id})
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

    test "renders a published note", %{site: site} do
      note =
        published_post(site, %{
          kind: :note,
          body: "A short update about [Once](https://buildonce.dev)."
        })

      stub(MediaStorage, :get, fn _key -> {:error, :not_found} end)
      expect(Carta, :render, fn _pool, html, _opts -> {:ok, "NOTE-JPEG:" <> html} end)
      stub(MediaStorage, :put, fn _key, _body, _content_type -> :ok end)

      assert {:ok, "NOTE-JPEG:" <> html} =
               OpenGraph.render(site, %{"kind" => "note", "id" => note.id})

      assert html =~ "A short update about Once."
      refute html =~ "[Once](https://buildonce.dev)"
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

    test "mints a signed note URL with the note kind", %{site: site} do
      note = published_post(site, %{kind: :note, body: "A short public update."})
      ctx = %{site: site, theme: site.theme, base_url: "https://example.test"}

      params =
        {:note, note}
        |> OpenGraph.image_url(ctx)
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.decode_query()

      assert params["kind"] == "note"
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

    test "changes the image URL when the selected theme changes", %{site: site} do
      post = published_post(site)
      base_context = %{site: site, theme: site.theme, base_url: "https://example.test"}
      darkroom_context = %{base_context | theme: ThemeDefaults.theme(site.id, "darkroom")}

      refute OpenGraph.image_url({:post, post}, base_context) ==
               OpenGraph.image_url({:post, post}, darkroom_context)
    end
  end
end
