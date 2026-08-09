defmodule Gesttalt.Plans do
  @moduledoc "Defines publishing capabilities available to every publication."

  alias Gesttalt.Sites.Site

  @publisher_features [:custom_domains, :media_uploads, :custom_themes]

  def available?(%Site{}, feature) when feature in @publisher_features, do: true

  def available?(%Site{}, feature) when feature in [:text_publishing, :programmatic_publishing],
    do: true

  def authorize(%Site{} = site, feature), do: if(available?(site, feature), do: :ok)
end
