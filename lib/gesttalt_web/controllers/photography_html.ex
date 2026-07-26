defmodule GesttaltWeb.PhotographyHTML do
  use GesttaltWeb, :html

  embed_templates "photography_html/*"

  def public_feed_url(site, anchor \\ nil) do
    domain = Enum.find(site.domains, &(&1.status == :active))
    path = "/photography#{anchor || ""}"

    if domain, do: "https://#{domain.hostname}#{path}", else: path
  end
end
