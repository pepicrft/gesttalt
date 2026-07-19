alias Boruta.Ecto.Scope
alias Gesttalt.Accounts
alias Gesttalt.Accounts.User
alias Gesttalt.Publishing
alias Gesttalt.Repo
alias Gesttalt.Sites

for {name, label} <- [
      {"content:read", "Read posts and pages"},
      {"content:write", "Create and edit posts and pages"},
      {"media:write", "Upload images"},
      {"mcp", "Publish through the Model Context Protocol"}
    ] do
  %Scope{}
  |> Scope.changeset(%{name: name, label: label, public: true})
  |> Repo.insert!(on_conflict: {:replace, [:label, :public, :updated_at]}, conflict_target: :name)
end

bootstrap_email =
  System.get_env("GESTTALT_SEED_EMAIL") ||
    if(Application.get_env(:gesttalt, :seed_demo), do: "demo@gesttalt.local")

if bootstrap_email do
  user =
    case Accounts.get_user_by_email(bootstrap_email) do
      %User{} = user ->
        user

      nil ->
        {:ok, user} = Accounts.register_user(%{email: bootstrap_email})
        {:ok, user} = user |> User.confirm_changeset() |> Repo.update()
        user
    end

  password =
    System.get_env("GESTTALT_SEED_PASSWORD") ||
      if(Application.get_env(:gesttalt, :seed_demo), do: "gesttalt-development")

  user =
    if password && is_nil(user.hashed_password) do
      {:ok, user} =
        user
        |> User.password_changeset(%{password: password, password_confirmation: password})
        |> Repo.update()

      user
    else
      user
    end

  {:ok, site} = Sites.ensure_site_for_user(user)

  site =
    case System.get_env("GESTTALT_SEED_SITE_NAME") do
      nil ->
        site

      name ->
        {:ok, site} = Sites.update_site(site, %{name: name})
        site
    end

  if domain_name = System.get_env("GESTTALT_SEED_DOMAIN") do
    if !Enum.any?(Sites.list_domains(site), &(&1.hostname == domain_name)) do
      {:ok, domain} = Sites.add_custom_domain(site, %{hostname: domain_name})

      {:ok, _domain} =
        domain
        |> Gesttalt.Sites.Domain.changeset(%{
          status: :active,
          verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end

  if Application.get_env(:gesttalt, :seed_demo) and Publishing.list_posts(site) == [] do
    {:ok, _post} =
      Publishing.create_post(site, %{
        title: "The shape of a quiet web",
        excerpt: "Publishing should feel like placing a page on your own desk.",
        body:
          "Gesttalt keeps the writing surface calm and the publishing surface open.\n\nEvery post remains yours, on an address you control.",
        status: :published,
        kind: :post,
        published_at:
          DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.truncate(:second)
      })

    {:ok, _post} =
      Publishing.create_post(site, %{
        title: "Themes are code",
        excerpt: "A conversational loop for Liquid templates and vanilla styles.",
        body:
          "Create an editing session with your agent and watch the preview respond immediately.",
        status: :published,
        kind: :post,
        published_at:
          DateTime.utc_now() |> DateTime.add(-172_800, :second) |> DateTime.truncate(:second)
      })

    {:ok, _page} =
      Publishing.create_post(site, %{
        title: "About",
        excerpt: "An independent publication.",
        body: "This is a standalone page, rendered by the same Liquid theme.",
        status: :published,
        kind: :page
      })
  end
end
