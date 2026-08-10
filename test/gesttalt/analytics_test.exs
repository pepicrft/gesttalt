defmodule Gesttalt.AnalyticsTest do
  use Gesttalt.DataCase, async: true

  import Gesttalt.AccountsFixtures

  alias Gesttalt.Analytics

  test "summarizes recent page views by path for one publication" do
    site = site_fixture()
    other_site = site_fixture()

    {:ok, _} = Analytics.record_page_view(site, %{path: "/", country: "ES"})
    {:ok, _} = Analytics.record_page_view(site, %{path: "/", country: "ES"})
    {:ok, _} = Analytics.record_page_view(site, %{path: "/blog/a-post", country: "US"})
    {:ok, _} = Analytics.record_page_view(other_site, %{path: "/"})

    assert Analytics.summary(site) == %{
             locations: [
               %{country: "ES", label: "Spain", latitude: 40, longitude: -4, views: 2},
               %{country: "US", label: "United States", latitude: 40, longitude: -99, views: 1}
             ],
             page_views: 3,
             period: 30,
             top_pages: [%{path: "/", views: 2}, %{path: "/blog/a-post", views: 1}]
           }
  end

  test "accepts only the available reporting periods" do
    assert Analytics.period("7") == 7
    assert Analytics.period("30") == 30
    assert Analytics.period("90") == 90
    assert Analytics.period("365") == 30
  end

  test "rejects paths that are not public paths" do
    assert {:error, changeset} = Analytics.record_page_view(site_fixture(), %{path: "blog"})
    assert "has invalid format" in errors_on(changeset).path
  end
end
