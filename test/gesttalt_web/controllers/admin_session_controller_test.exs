defmodule GesttaltWeb.AdminSessionControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Sites
  alias GesttaltWeb.AdminSession

  setup do
    user = AccountsFixtures.user_fixture()
    site = AccountsFixtures.site_fixture(user)
    domain = Enum.find(site.domains, &(&1.status == :active))

    %{domain: domain, site: site, user: user}
  end

  test "signs the owner into the admin on their publication domain", %{
    conn: conn,
    domain: domain,
    user: user
  } do
    return_to = "/admin/posts/new?kind=post"

    prepare_conn =
      conn
      |> Map.put(:host, domain.hostname)
      |> get(~p"/admin/session/prepare?return_to=#{return_to}")

    state = get_session(prepare_conn, :admin_handoff_state)
    assert AdminSession.valid_state?(state)

    start_uri = prepare_conn |> redirected_to() |> URI.parse()
    assert start_uri.host == Sites.platform_host()
    assert start_uri.path == "/admin/session/start"

    platform_conn =
      conn
      |> log_in_user(user)
      |> Map.put(:host, Sites.platform_host())
      |> get(start_uri.path <> "?" <> start_uri.query)

    complete_uri = platform_conn |> redirected_to() |> URI.parse()
    assert complete_uri.host == domain.hostname
    assert complete_uri.path =~ ~r|^/admin/session/complete/|

    complete_conn =
      conn
      |> init_test_session(%{admin_handoff_state: state})
      |> Map.put(:host, domain.hostname)
      |> get(complete_uri.path <> "?" <> complete_uri.query)

    assert redirected_to(complete_conn) == return_to
    assert get_session(complete_conn, :user_token)
    refute get_session(complete_conn, :admin_handoff_state)

    dashboard_conn =
      complete_conn
      |> recycle()
      |> Map.put(:host, domain.hostname)
      |> get(~p"/admin/")

    assert html_response(dashboard_conn, 200) =~ "Content"
    assert get_resp_header(dashboard_conn, "x-frame-options") == ["DENY"]

    assert get_resp_header(dashboard_conn, "content-security-policy") == [
             "frame-ancestors 'none'"
           ]
  end

  test "starts the central sign-in flow for an anonymous publication-domain request", %{
    conn: conn,
    domain: domain
  } do
    conn = conn |> Map.put(:host, domain.hostname) |> get(~p"/admin/analytics?period=7")

    assert redirected_to(conn) ==
             "/admin/session/prepare?return_to=%2Fadmin%2Fanalytics%3Fperiod%3D7"
  end

  test "requires an authenticated platform session before issuing a handoff", %{
    conn: conn,
    domain: domain
  } do
    state = AdminSession.generate_state()

    conn =
      get(
        conn,
        ~p"/admin/session/start?host=#{domain.hostname}&state=#{state}&return_to=/admin/"
      )

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) =~ "/admin/session/start?"
  end

  test "refuses to issue a handoff for a publication owned by another user", %{
    conn: conn,
    domain: domain
  } do
    other_user = AccountsFixtures.user_fixture()
    state = AdminSession.generate_state()

    conn =
      conn
      |> log_in_user(other_user)
      |> get(~p"/admin/session/start?host=#{domain.hostname}&state=#{state}&return_to=/admin/")

    assert response(conn, 404) == "Unknown publication"
  end

  test "refuses to issue a handoff from a publication host", %{
    conn: conn,
    domain: domain,
    user: user
  } do
    state = AdminSession.generate_state()

    conn =
      conn
      |> log_in_user(user)
      |> Map.put(:host, domain.hostname)
      |> get(~p"/admin/session/start?host=#{domain.hostname}&state=#{state}&return_to=/admin/")

    assert response(conn, 404) == "Unknown publication"
  end

  test "rejects a handoff when the publication browser state does not match", %{
    conn: conn,
    domain: domain,
    user: user
  } do
    state = AdminSession.generate_state()
    {:ok, token} = Gesttalt.Accounts.generate_admin_handoff_token(user, domain.hostname, state)

    conn =
      conn
      |> init_test_session(%{admin_handoff_state: AdminSession.generate_state()})
      |> Map.put(:host, domain.hostname)
      |> get(~p"/admin/session/complete/#{token}")

    assert response(conn, 401) == "Admin sign-in could not be completed"
    refute get_session(conn, :user_token)
  end

  test "rejects a replayed handoff token", %{conn: conn, domain: domain, user: user} do
    state = AdminSession.generate_state()
    {:ok, token} = Gesttalt.Accounts.generate_admin_handoff_token(user, domain.hostname, state)
    path = ~p"/admin/session/complete/#{token}"

    first_conn =
      conn
      |> init_test_session(%{admin_handoff_state: state})
      |> Map.put(:host, domain.hostname)
      |> get(path)

    assert redirected_to(first_conn) == ~p"/admin/"

    replay_conn =
      conn
      |> recycle()
      |> init_test_session(%{admin_handoff_state: state})
      |> Map.put(:host, domain.hostname)
      |> get(path)

    assert response(replay_conn, 401) == "Admin sign-in could not be completed"
  end

  test "keeps an authenticated user out of another publication's admin", %{
    conn: conn,
    domain: domain
  } do
    other_user = AccountsFixtures.user_fixture()

    conn =
      conn
      |> log_in_user(other_user)
      |> Map.put(:host, domain.hostname)
      |> get(~p"/admin/")

    assert response(conn, 404) == "Unknown publication"
  end

  test "rejects unknown hosts before rendering an admin page", %{conn: conn, user: user} do
    conn = conn |> log_in_user(user) |> Map.put(:host, "unknown.example") |> get(~p"/admin/")

    assert response(conn, 404) == "Unknown publication"
  end

  test "keeps return paths local to the protected admin", %{conn: conn, domain: domain} do
    conn =
      conn
      |> Map.put(:host, domain.hostname)
      |> get(~p"/admin/session/prepare?return_to=https://attacker.example/steal")

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["return_to"] == "/admin/"
  end
end
