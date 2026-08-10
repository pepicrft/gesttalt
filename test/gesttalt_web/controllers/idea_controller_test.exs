defmodule GesttaltWeb.IdeaControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.Publishing
  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "creates, edits, and deletes an idea from the dashboard", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)

    created =
      conn
      |> post(~p"/admin/ideas", %{
        idea: %{title: "Ask about favorite books", notes: "Bring three."}
      })

    assert redirected_to(created) == ~p"/admin/ideas"
    [idea] = Publishing.list_ideas(site)

    dashboard = created |> recycle() |> get(~p"/admin/ideas") |> html_response(200)
    assert dashboard =~ ~s(id="admin-ideas")
    assert dashboard =~ "Ask about favorite books"
    assert dashboard =~ "Bring three."

    updated =
      created
      |> recycle()
      |> put(~p"/admin/ideas/#{idea}", %{
        idea: %{title: "Ask about favorite films", notes: "Bring two."}
      })

    assert redirected_to(updated) == ~p"/admin/ideas"
    assert Publishing.get_idea(site, idea.id).title == "Ask about favorite films"

    deleted = updated |> recycle() |> delete(~p"/admin/ideas/#{idea}")
    assert redirected_to(deleted) == ~p"/admin/ideas"
    assert Publishing.get_idea(site, idea.id) == nil
  end
end
