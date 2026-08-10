defmodule GesttaltWeb.AdminHTML do
  @moduledoc "Editor pages for managing Gesttalt articles."

  use GesttaltWeb, :html

  embed_templates "admin_html/*"

  def datetime_value(%Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :published_at) do
      %DateTime{} = datetime -> Calendar.strftime(datetime, "%Y-%m-%dT%H:%M")
      _other -> ""
    end
  end

  def public_url(origin, site, post) do
    domain = Enum.find(site.domains, &(&1.status == :active))

    path =
      case post.kind do
        :post -> "/blog/#{post.slug}/"
        :note -> "/notes/#{post.id}/"
        :page -> "/#{post.slug}/"
      end

    if domain,
      do: "#{origin |> URI.parse() |> Map.put(:host, domain.hostname) |> URI.to_string()}#{path}",
      else: path
  end
end
