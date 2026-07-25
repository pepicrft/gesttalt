defmodule GesttaltWeb.OpenGraphControllerTest do
  use GesttaltWeb.ConnCase, async: true
  use Mimic

  alias Gesttalt.MediaStorage
  alias Gesttalt.OpenGraph.Signer

  import Gesttalt.AccountsFixtures
  import Gesttalt.PublishingFixtures

  setup do
    user = user_fixture()
    site = site_fixture(user)
    host = site.domains |> List.first() |> Map.fetch!(:hostname)
    %{site: site, host: host}
  end

  defp secret do
    :gesttalt
    |> Application.fetch_env!(GesttaltWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end

  defp signed_query(params),
    do: URI.encode_query(Map.put(params, "sig", Signer.sign(params, secret())))

  test "rejects a request without a signature", %{conn: conn, host: host, site: site} do
    params = %{"kind" => "post", "id" => Ecto.UUID.generate(), "site" => site.id, "v" => "0-0"}

    conn =
      conn
      |> Map.put(:host, host)
      |> get("/og-image?" <> URI.encode_query(params))

    assert response(conn, 403)
  end

  test "rejects a request with a tampered signature", %{conn: conn, host: host, site: site} do
    params = %{"kind" => "post", "id" => Ecto.UUID.generate(), "site" => site.id, "v" => "0-0"}
    query = signed_query(params)
    tampered = String.replace(query, "v=0-0", "v=9-9")

    conn = conn |> Map.put(:host, host) |> get("/og-image?" <> tampered)

    assert response(conn, 403)
  end

  test "returns 404 for a validly signed but unpublished post", %{
    conn: conn,
    host: host,
    site: site
  } do
    draft = post_fixture(%{site: site})
    params = %{"kind" => "post", "id" => draft.id, "site" => site.id, "v" => "0-0"}

    conn = conn |> Map.put(:host, host) |> get("/og-image?" <> signed_query(params))

    assert response(conn, 404)
  end

  test "returns 404 for a validly signed unknown identifier", %{
    conn: conn,
    host: host,
    site: site
  } do
    params = %{"kind" => "post", "id" => Ecto.UUID.generate(), "site" => site.id, "v" => "0-0"}

    conn = conn |> Map.put(:host, host) |> get("/og-image?" <> signed_query(params))

    assert response(conn, 404)
  end

  test "serves a signed, published image as a cached JPEG", %{conn: conn, host: host, site: site} do
    {:ok, post} = Gesttalt.Publishing.publish_post(post_fixture(%{site: site}))
    params = %{"kind" => "post", "id" => post.id, "site" => site.id, "v" => "0-0"}

    stub(MediaStorage, :get, fn _key -> {:ok, "STORED-JPEG"} end)
    reject(&Carta.render/3)

    conn = conn |> Map.put(:host, host) |> get("/og-image?" <> signed_query(params))

    assert "STORED-JPEG" = response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
  end
end
