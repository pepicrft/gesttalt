defmodule Gesttalt.Analytics do
  @moduledoc "Privacy-preserving, first-party publication page-view counts."

  import Ecto.Query, warn: false

  alias Gesttalt.Analytics.Location
  alias Gesttalt.Analytics.PageView
  alias Gesttalt.Repo
  alias Gesttalt.Sites.Site

  @periods [7, 30, 90]

  def record_page_view(%Site{} = site, attrs) do
    %PageView{}
    |> PageView.changeset(Map.put(attrs, :site_id, site.id))
    |> Repo.insert()
  end

  def period(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} when days in @periods -> days
      _invalid -> 30
    end
  end

  def period(value) when value in @periods, do: value
  def period(_value), do: 30

  def summary(%Site{id: site_id}, period \\ 30) do
    period = period(period)
    since = DateTime.add(DateTime.utc_now(), -period, :day)

    page_views =
      PageView
      |> where([page_view], page_view.site_id == ^site_id and page_view.inserted_at >= ^since)
      |> Repo.aggregate(:count)

    top_pages =
      PageView
      |> where([page_view], page_view.site_id == ^site_id and page_view.inserted_at >= ^since)
      |> group_by([page_view], page_view.path)
      |> select([page_view], %{path: page_view.path, views: count(page_view.id)})
      |> order_by([page_view], desc: count(page_view.id), asc: page_view.path)
      |> limit(10)
      |> Repo.all()

    locations =
      PageView
      |> where(
        [page_view],
        page_view.site_id == ^site_id and page_view.inserted_at >= ^since and
          not is_nil(page_view.country)
      )
      |> group_by([page_view], page_view.country)
      |> select([page_view], %{country: page_view.country, views: count(page_view.id)})
      |> order_by([page_view], desc: count(page_view.id), asc: page_view.country)
      |> limit(10)
      |> Repo.all()
      |> Enum.map(&Location.describe(&1.country, &1.views))

    %{page_views: page_views, top_pages: top_pages, locations: locations, period: period}
  end
end
