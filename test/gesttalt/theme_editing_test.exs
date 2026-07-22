defmodule Gesttalt.ThemeEditingTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing

  setup do
    site = AccountsFixtures.site_fixture()
    {:ok, site} = Sites.update_billing(site, %{subscription_status: :trialing})
    {:ok, session} = ThemeEditing.create(site)

    on_exit(fn ->
      _result = ThemeEditing.discard(session.id, site)
    end)

    %{session: session, site: site}
  end

  test "keeps edits isolated until the session is published", %{session: session, site: site} do
    original_theme = Sites.get_theme!(site)
    Phoenix.PubSub.subscribe(Gesttalt.PubSub, ThemeEditing.topic(session.id))

    assert {:ok, updated_session} =
             ThemeEditing.update(session.id, site, %{
               "name" => "Conversation",
               "stylesheet" => "body { color: rebeccapurple; }",
               "variables" => %{"colors" => %{"primary" => "#d73a49"}}
             })

    assert updated_session.revision == 1
    assert updated_session.theme.name == "Conversation"
    assert updated_session.theme.variables["colors"]["primary"] == "#d73a49"
    assert updated_session.theme.variables["colors"]["background"] == "#fdfbf7"
    assert_receive {:theme_editing_session_updated, 1}

    active_theme = Sites.get_theme!(site)
    assert active_theme.name == original_theme.name
    assert active_theme.stylesheet == original_theme.stylesheet
    assert active_theme.variables == original_theme.variables

    assert {:ok, published_theme} = ThemeEditing.publish(session.id, site)
    assert published_theme.name == "Conversation"
    assert Sites.get_theme!(site).stylesheet == "body { color: rebeccapurple; }"
    assert Sites.get_theme!(site).variables["colors"]["primary"] == "#d73a49"
    assert_receive {:theme_editing_session_closed, :published}
    assert {:error, :not_found} = ThemeEditing.fetch(session.id)
  end

  test "discards a draft without changing the active theme", %{session: session, site: site} do
    original_theme = Sites.get_theme!(site)

    assert {:ok, _session} = ThemeEditing.update(session.id, site, %{name: "Temporary"})
    assert :ok = ThemeEditing.discard(session.id, site)

    assert Sites.get_theme!(site).name == original_theme.name
    assert {:error, :not_found} = ThemeEditing.fetch(session.id)
  end

  test "hides sessions from other publications", %{session: session, site: site} do
    other_site = AccountsFixtures.site_fixture()

    assert {:error, :not_found} = ThemeEditing.fetch(session.id, other_site)
    assert {:error, :not_found} = ThemeEditing.update(session.id, other_site, %{name: "Nope"})
    assert {:error, :not_found} = ThemeEditing.discard(session.id, other_site)

    assert :ok = ThemeEditing.discard(session.id, site)
  end

  test "rejects invalid, oversized, empty, and unchanged edits", %{session: session, site: site} do
    assert {:error, %Ecto.Changeset{}} = ThemeEditing.update(session.id, site, %{name: ""})

    assert {:error, %Ecto.Changeset{}} =
             ThemeEditing.update(session.id, site, %{
               variables: %{"colors" => %{"surprise" => "hotpink"}}
             })

    assert {:error, %Ecto.Changeset{}} =
             ThemeEditing.update(session.id, site, %{
               stylesheet: String.duplicate("x", 512_001)
             })

    assert {:error, :no_theme_changes} = ThemeEditing.update(session.id, site, %{})

    assert {:error, :no_theme_changes} =
             ThemeEditing.update(session.id, site, %{name: session.theme.name})

    assert {:ok, %{revision: 0}} = ThemeEditing.fetch(session.id, site)

    assert :ok = ThemeEditing.discard(session.id, site)
  end

  test "serializes concurrent edits into monotonic revisions", %{session: session, site: site} do
    revisions =
      1..12
      |> Task.async_stream(
        fn index -> ThemeEditing.update(session.id, site, %{name: "Draft #{index}"}) end,
        max_concurrency: 12,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, updated_session}} -> updated_session.revision end)

    assert Enum.sort(revisions) == Enum.to_list(1..12)
    assert {:ok, %{revision: 12}} = ThemeEditing.fetch(session.id, site)
  end

  test "caps concurrent in-memory drafts per publication", %{session: first_session, site: site} do
    other_sessions =
      for _index <- 2..5 do
        assert {:ok, session} = ThemeEditing.create(site)
        session
      end

    on_exit(fn ->
      Enum.each(other_sessions, fn session ->
        _result = ThemeEditing.discard(session.id, site)
      end)
    end)

    assert {:error, :too_many_sessions} = ThemeEditing.create(site)
    assert :ok = ThemeEditing.discard(first_session.id, site)
    assert {:ok, replacement} = ThemeEditing.create(site)
    assert :ok = ThemeEditing.discard(replacement.id, site)
  end

  test "locks the draft while a publication snapshot is in flight", %{
    session: session,
    site: site
  } do
    [{session_process, _value}] =
      Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session.id)

    test_process = self()

    publisher =
      spawn(fn ->
        result = GenServer.call(session_process, {:begin_publish, site.id})
        send(test_process, {:publication_started, self(), result})

        receive do
          :resume ->
            result = GenServer.call(session_process, {:resume_publish, site.id})
            send(test_process, {:publication_resumed, self(), result})
        end
      end)

    assert_receive {:publication_started, ^publisher, {:ok, _theme}}
    assert {:error, :publishing} = ThemeEditing.update(session.id, site, %{name: "Too late"})
    assert {:error, :publishing} = ThemeEditing.discard(session.id, site)

    send(publisher, :resume)
    assert_receive {:publication_resumed, ^publisher, :ok}
    assert {:ok, _session} = ThemeEditing.update(session.id, site, %{name: "Available again"})
  end

  test "keeps a draft open when the publishing entitlement lapses", %{
    session: session,
    site: site
  } do
    {:ok, inactive_site} = Sites.update_billing(site, %{subscription_status: :inactive})

    assert {:error, :subscription_required} = ThemeEditing.publish(session.id, inactive_site)
    assert {:ok, _session} = ThemeEditing.fetch(session.id, site)
  end

  test "unlocks a draft when persistence raises", %{session: session, site: site} do
    site |> Sites.get_theme!() |> Repo.delete!()

    assert_raise Ecto.NoResultsError, fn -> ThemeEditing.publish(session.id, site) end
    assert {:ok, _session} = ThemeEditing.update(session.id, site, %{name: "Still editable"})
  end

  test "expires a session and tells connected previews to close", %{session: session} do
    Phoenix.PubSub.subscribe(Gesttalt.PubSub, ThemeEditing.topic(session.id))

    [{session_process, _value}] =
      Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session.id)

    monitor = Process.monitor(session_process)
    send(session_process, :expire)

    assert_receive {:theme_editing_session_closed, :expired}
    assert_receive {:DOWN, ^monitor, :process, ^session_process, :normal}
    assert {:error, :not_found} = ThemeEditing.fetch(session.id)
  end
end
