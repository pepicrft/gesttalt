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

  def public_url(site, post) do
    domain = Enum.find(site.domains, &(&1.status == :active))
    path = if post.kind == :post, do: "/blog/#{post.slug}/", else: "/#{post.slug}/"
    if domain, do: "https://#{domain.hostname}#{path}", else: path
  end
end
