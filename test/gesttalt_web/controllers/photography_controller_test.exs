defmodule GesttaltWeb.PhotographyControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.Photography
  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "publishes a photograph from the dashboard and renders it in the public feed", %{
    conn: conn,
    user: user
  } do
    {:ok, site} = Sites.ensure_site_for_user(user)
    upload = upload_fixture("window.png", "window light")

    conn =
      post(conn, ~p"/admin/photography", %{
        "photo" => %{
          "file" => upload,
          "alt_text" => "Light falling through a tall window",
          "caption" => "A slow afternoon. <script>alert('no')</script>",
          "status" => "published"
        }
      })

    assert redirected_to(conn) == ~p"/admin/photography"
    assert [photo] = Photography.list_photos(site)
    assert photo.status == :published

    dashboard = conn |> recycle() |> get(~p"/admin/photography") |> html_response(200)
    assert dashboard =~ "A slow afternoon."
    assert dashboard =~ "Light falling through a tall window"
    assert dashboard =~ ~s(data-status="published")

    host = site.domains |> List.first() |> Map.fetch!(:hostname)

    public_feed =
      conn
      |> recycle()
      |> Map.put(:host, host)
      |> get(~p"/photography")
      |> html_response(200)

    assert public_feed =~ ~s(id="site-photography")
    assert public_feed =~ ~s(id="photo-#{photo.id}")
    assert public_feed =~ "A slow afternoon."
    assert public_feed =~ ~s(alt="Light falling through a tall window")
    refute public_feed =~ "<script>alert('no')</script>"
    assert public_feed =~ "&lt;script&gt;alert"
  end

  test "keeps dashboard drafts out of the public feed", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)
    upload = upload_fixture("draft.png", "draft")

    conn =
      post(conn, ~p"/admin/photography", %{
        "photo" => %{
          "file" => upload,
          "alt_text" => "An unpublished contact sheet",
          "status" => "draft"
        }
      })

    assert redirected_to(conn) == ~p"/admin/photography"
    assert [photo] = Photography.list_photos(site)
    assert photo.status == :draft

    host = site.domains |> List.first() |> Map.fetch!(:hostname)

    public_feed =
      conn
      |> recycle()
      |> Map.put(:host, host)
      |> get(~p"/photography")
      |> html_response(200)

    refute public_feed =~ "An unpublished contact sheet"
    assert public_feed =~ "No photographs have been published yet."
  end

  defp upload_fixture(filename, contents) do
    path = Path.join(System.tmp_dir!(), "gesttalt-photo-#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{path: path, filename: filename, content_type: "image/png"}
  end
end
