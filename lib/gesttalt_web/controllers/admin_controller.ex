defmodule GesttaltWeb.AdminController do
  use GesttaltWeb, :controller

  alias Gesttalt.Analytics
  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.Post

  def index(conn, _params) do
    site = current_site(conn)

    render(conn, :index,
      page_title: "Editor",
      posts: Publishing.list_posts(site),
      public_origin: public_origin(conn),
      site: site
    )
  end

  def analytics(conn, params) do
    site = current_site(conn)
    period = Analytics.period(params["period"])

    conn
    |> put_view(GesttaltWeb.AnalyticsHTML)
    |> render(:show,
      page_title: "Analytics",
      site: site,
      summary: Analytics.summary(site, period)
    )
  end

  def new(conn, _params),
    do: render_form(conn, Publishing.change_post(%Post{}), "New post", ~p"/admin/posts")

  def new_note(conn, _params),
    do:
      render_form(conn, Publishing.change_post(%Post{kind: :note}), "New note", ~p"/admin/posts")

  def create(conn, %{"post" => attrs}) do
    case Publishing.create_post(current_site(conn), attrs) do
      {:ok, post} ->
        conn |> put_flash(:info, "Draft saved.") |> redirect(to: ~p"/admin/posts/#{post}/edit")

      {:error, changeset} ->
        render_form(conn, changeset, "New post", ~p"/admin/posts")
    end
  end

  def edit(conn, %{"id" => id}) do
    post = Publishing.get_post!(current_site(conn), id)

    render_form(
      conn,
      Publishing.change_post(post),
      "Edit post",
      ~p"/admin/posts/#{post}",
      "put"
    )
  end

  def update(conn, %{"id" => id, "post" => attrs}) do
    post = Publishing.get_post!(current_site(conn), id)

    case Publishing.update_post(post, attrs) do
      {:ok, updated_post} ->
        conn
        |> put_flash(:info, "Post saved.")
        |> redirect(to: ~p"/admin/posts/#{updated_post}/edit")

      {:error, changeset} ->
        render_form(conn, changeset, "Edit post", ~p"/admin/posts/#{post}", "put")
    end
  end

  def publish(conn, %{"id" => id}) do
    current_site(conn) |> Publishing.get_post!(id) |> Publishing.publish_post()
    conn |> put_flash(:info, "Post published.") |> redirect(to: ~p"/admin/")
  end

  def unpublish(conn, %{"id" => id}) do
    current_site(conn) |> Publishing.get_post!(id) |> Publishing.unpublish_post()
    conn |> put_flash(:info, "Post moved to drafts.") |> redirect(to: ~p"/admin/")
  end

  def delete(conn, %{"id" => id}) do
    current_site(conn) |> Publishing.get_post!(id) |> Publishing.delete_post()
    conn |> put_flash(:info, "Post deleted.") |> redirect(to: ~p"/admin/")
  end

  defp render_form(conn, changeset, title, action, method \\ "post") do
    render(conn, :edit,
      page_title: title,
      changeset: changeset,
      post: changeset.data,
      site: current_site(conn),
      form_action: action,
      form_method: method
    )
  end

  defp current_site(conn), do: conn.assigns.current_site

  defp public_origin(conn) do
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    "#{conn.scheme}://#{conn.host}#{port}"
  end
end
