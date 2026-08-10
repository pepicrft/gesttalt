defmodule Gesttalt.Plans do
  @moduledoc "Defines publishing capabilities available to every publication."

  alias Gesttalt.Sites.Site

  def authorize(%Site{}, :custom_themes), do: :ok
end
