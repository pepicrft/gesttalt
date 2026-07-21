defmodule GesttaltWeb.AdminControllerTest do
  use GesttaltWeb.ConnCase, async: true

  import Gesttalt.PublishingFixtures

  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "shows the publication date for published content", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)
    published_at = ~U[2017-12-25 12:00:00Z]

    post_fixture(%{
      site: site,
      title: "A post from the archive",
      status: :published,
      published_at: published_at
    })

    response = conn |> get(~p"/admin/") |> html_response(200)

    assert response =~ "25 Dec 2017, 12:00"
    assert response =~ ~s(datetime="2017-12-25T12:00:00Z")
  end
end
