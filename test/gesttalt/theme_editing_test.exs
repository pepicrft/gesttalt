defmodule Gesttalt.ThemeEditingTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing
  alias Gesttalt.ThemeEditing.StoredSession

  setup do
    site = AccountsFixtures.site_fixture()
    {:ok, site} = Sites.update_billing(site, %{subscription_status: :trialing})
    {:ok, session} = ThemeEditing.create(site)

    on_exit(fn ->
      terminate_session(session.id)
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

  test "tracks connected browser previews and navigates a selected client", %{
    session: session,
    site: site
  } do
    test_process = self()

    client =
      spawn(fn ->
        receive do
          {:theme_preview_navigate, page} ->
            send(test_process, {:preview_navigated, page})
        end
      end)

    assert {:ok, _client} =
             ThemeEditing.connect_preview(
               session.id,
               site,
               "browser-client-0001",
               client,
               %{
                 page: %{"kind" => "home", "title" => site.name},
                 path: "/",
                 preview_path: ThemeEditing.preview_path(session.id),
                 screenshots_enabled: false,
                 viewport: %{device_pixel_ratio: 2, height: 800, width: 1_200}
               }
             )

    assert {:ok, [preview]} = ThemeEditing.list_previews(session.id, site)
    assert preview.client_id == "browser-client-0001"
    assert preview.path == "/"
    assert preview.viewport.width == 1_200
    refute preview.screenshots_enabled

    assert {:ok, navigated} =
             ThemeEditing.navigate_preview(
               session.id,
               site,
               "browser-client-0001",
               "/"
             )

    assert navigated.page == %{"kind" => "home", "title" => site.name}
    assert_receive {:preview_navigated, %{"kind" => "home"}}

    assert_eventually(fn -> ThemeEditing.list_previews(session.id, site) == {:ok, []} end)
  end

  test "returns a client-provided screenshot without retaining its bytes", %{
    session: session,
    site: site
  } do
    test_process = self()

    client =
      spawn(fn ->
        receive do
          {:theme_preview_capture, request_id} ->
            result =
              ThemeEditing.complete_preview_screenshot(
                session.id,
                "browser-client-0002",
                request_id,
                %{
                  data: "png image bytes",
                  height: 720,
                  mime_type: "image/png",
                  width: 1_280
                }
              )

            send(test_process, {:screenshot_completed, result})
        end
      end)

    assert {:ok, _client} =
             ThemeEditing.connect_preview(
               session.id,
               site,
               "browser-client-0002",
               client,
               %{
                 page: %{"kind" => "home", "title" => site.name},
                 path: "/",
                 preview_path: ThemeEditing.preview_path(session.id),
                 screenshots_enabled: true,
                 viewport: %{device_pixel_ratio: 1, height: 720, width: 1_280}
               }
             )

    assert {:ok, screenshot} =
             ThemeEditing.capture_preview(session.id, site, "browser-client-0002")

    assert screenshot.data == "png image bytes"
    assert screenshot.mime_type == "image/png"
    assert screenshot.width == 1_280
    assert screenshot.height == 720
    assert screenshot.path == "/"
    assert_receive {:screenshot_completed, :ok}

    assert_eventually(fn -> ThemeEditing.list_previews(session.id, site) == {:ok, []} end)
  end

  test "requires screenshot permission and an unambiguous connected client", %{
    session: session,
    site: site
  } do
    client = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, _client} =
             ThemeEditing.connect_preview(
               session.id,
               site,
               "browser-client-0003",
               client,
               %{
                 page: %{"kind" => "home", "title" => site.name},
                 path: "/",
                 preview_path: ThemeEditing.preview_path(session.id),
                 screenshots_enabled: false,
                 viewport: %{}
               }
             )

    assert {:error, :screenshot_permission_required} =
             ThemeEditing.capture_preview(session.id, site)

    Process.exit(client, :kill)
  end

  test "caps concurrent durable drafts per publication", %{session: first_session, site: site} do
    other_sessions =
      for _index <- 2..5 do
        assert {:ok, session} = ThemeEditing.create(site)
        session
      end

    on_exit(fn ->
      Enum.each(other_sessions, &terminate_session(&1.id))
    end)

    assert {:error, :too_many_sessions} = ThemeEditing.create(site)
    assert :ok = ThemeEditing.discard(first_session.id, site)
    assert {:ok, replacement} = ThemeEditing.create(site)
    assert :ok = ThemeEditing.discard(replacement.id, site)
  end

  test "restores a durable draft after its editing process stops", %{
    session: session,
    site: site
  } do
    assert {:ok, %{revision: 1}} =
             ThemeEditing.update(session.id, site, %{
               name: "Deployment proof",
               variables: %{"colors" => %{"primary" => "#ff4f81"}}
             })

    [{original_process, _value}] =
      Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session.id)

    monitor = Process.monitor(original_process)

    assert :ok =
             DynamicSupervisor.terminate_child(
               Gesttalt.ThemeEditing.SessionSupervisor,
               original_process
             )

    assert_receive {:DOWN, ^monitor, :process, ^original_process, :shutdown}

    assert {:ok, restored} = ThemeEditing.fetch(session.id, site)
    assert restored.revision == 1
    assert restored.theme.name == "Deployment proof"
    assert restored.theme.variables["colors"]["primary"] == "#ff4f81"

    assert [{restored_process, _value}] =
             Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session.id)

    refute restored_process == original_process
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

  test "publishes a draft during early access without a subscription", %{
    session: session,
    site: site
  } do
    {:ok, inactive_site} = Sites.update_billing(site, %{subscription_status: :inactive})

    assert {:ok, _theme} = ThemeEditing.publish(session.id, inactive_site)
    assert {:error, :not_found} = ThemeEditing.fetch(session.id, site)
  end

  test "creates an override when a saved theme is removed before publication", %{
    session: session,
    site: site
  } do
    {:ok, theme} = Sites.update_theme(site, %{})
    Repo.delete!(theme)

    assert {:ok, published_theme} = ThemeEditing.publish(session.id, site)
    assert published_theme.id
    assert {:error, :not_found} = ThemeEditing.fetch(session.id)
  end

  test "expires a session and tells connected previews to close", %{session: session} do
    Phoenix.PubSub.subscribe(Gesttalt.PubSub, ThemeEditing.topic(session.id))

    {1, _result} =
      StoredSession
      |> where([stored], stored.id == ^session.id)
      |> Repo.update_all(set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])

    [{session_process, _value}] =
      Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session.id)

    monitor = Process.monitor(session_process)
    send(session_process, :expire)

    assert_receive {:theme_editing_session_closed, :expired}
    assert_receive {:DOWN, ^monitor, :process, ^session_process, :normal}
    assert {:error, :not_found} = ThemeEditing.fetch(session.id)
  end

  defp assert_eventually(assertion, attempts \\ 20)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      assert true
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")

  defp terminate_session(session_id) do
    case Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session_id) do
      [{process, _value}] ->
        DynamicSupervisor.terminate_child(Gesttalt.ThemeEditing.SessionSupervisor, process)

      [] ->
        :ok
    end
  end
end
