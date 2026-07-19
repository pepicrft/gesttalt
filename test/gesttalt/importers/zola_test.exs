defmodule Gesttalt.Importers.ZolaTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Importers.Zola
  alias Gesttalt.Publishing
  alias Gesttalt.Sites

  setup do
    root = Path.join(System.tmp_dir!(), "gesttalt-zola-#{System.unique_integer([:positive])}")
    blog = Path.join([root, "content", "blog"])
    File.mkdir_p!(blog)
    on_exit(fn -> File.rm_rf!(root) end)

    user = AccountsFixtures.user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)
    %{blog: blog, root: root, site: site}
  end

  test "preserves front matter and uses the description for an intentionally empty post", %{
    blog: blog,
    root: root,
    site: site
  } do
    File.write!(
      Path.join(blog, "talk.md"),
      """
      +++
      title = "A recorded talk"
      date = 2019-07-09T12:00:00+00:00
      slug = "recorded-talk"
      description = "The recording from the original publication."
      +++
      """
    )

    assert %{created: 1, skipped: 0, updated: 0} = Zola.import(site, root)

    post = Publishing.get_post_by_slug(site, "recorded-talk")
    assert post.title == "A recorded talk"
    assert post.excerpt == "The recording from the original publication."
    assert post.body == post.excerpt
    assert post.published_at == ~U[2019-07-09 12:00:00Z]
  end

  test "updates a matching slug when the import is repeated", %{
    blog: blog,
    root: root,
    site: site
  } do
    path = Path.join(blog, "note.md")

    File.write!(path, "+++\ntitle = \"First\"\nslug = \"note\"\n+++\nOriginal")
    assert %{created: 1} = Zola.import(site, root)

    File.write!(path, "+++\ntitle = \"Revised\"\nslug = \"note\"\n+++\nUpdated")
    assert %{updated: 1} = Zola.import(site, root)
    assert Publishing.get_post_by_slug(site, "note").title == "Revised"
  end
end
