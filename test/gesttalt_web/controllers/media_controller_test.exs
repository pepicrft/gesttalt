defmodule GesttaltWeb.MediaControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "uploads media during early access without a subscription", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)
    upload = upload_fixture("early-access.png", "early access image")

    conn =
      post(conn, ~p"/admin/media", %{
        "image" => %{"file" => upload, "alt_text" => "Early access"}
      })

    assert redirected_to(conn) == ~p"/admin/media"
    assert [image] = Sites.list_images(site)
    assert image.filename == "early-access.png"
    assert {:ok, _image} = Sites.delete_image(site, image.id)
  end

  test "renders media through an authenticated admin route", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)
    upload = upload_fixture("preview.png", "preview image")
    assert {:ok, image} = Sites.store_image(site, upload, "Preview")

    page = conn |> get(~p"/admin/media") |> html_response(200)
    assert page =~ ~p"/admin/media/#{image}/#{image.filename}"
    assert page =~ "![Preview](/media/#{image.id}/preview.png)"

    response = get(conn, ~p"/admin/media/#{image}/#{image.filename}")
    assert response(response, 200) == "preview image"
    assert get_resp_header(response, "content-type") == ["image/png; charset=utf-8"]
    assert get_resp_header(response, "cache-control") == ["private, max-age=3600"]

    assert {:ok, _image} = Sites.delete_image(site, image.id)
  end

  test "does not expose another account's media", %{conn: conn} do
    other_site = Gesttalt.AccountsFixtures.site_fixture()
    upload = upload_fixture("private.png", "private image")
    assert {:ok, image} = Sites.store_image(other_site, upload)

    assert_error_sent :not_found, fn ->
      get(conn, ~p"/admin/media/#{image}/#{image.filename}")
    end

    assert {:ok, _image} = Sites.delete_image(other_site, image.id)
  end

  defp upload_fixture(filename, contents) do
    path = Path.join(System.tmp_dir!(), "gesttalt-#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{path: path, filename: filename, content_type: "image/png"}
  end
end
