defmodule GesttaltWeb.ThemeControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "lists the built-in themes and selects one", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)

    response = conn |> get(~p"/admin/theme") |> html_response(200)

    for name <- ["Paper", "Ledger", "Darkroom", "Field Notes"] do
      assert response =~ name
    end

    conn = post(conn, ~p"/admin/theme", %{"built_in_theme" => "ledger"})

    assert redirected_to(conn) == ~p"/admin/theme"
    assert Sites.get_theme!(site).name == "Ledger"

    response = conn |> recycle() |> get(~p"/admin/theme") |> html_response(200)
    assert response =~ "--paper: #f5f1e8"
    assert response =~ "font-family: Georgia, &#39;Times New Roman&#39;, serif"
  end
end
