defmodule GesttaltWeb.AdminTheme do
  @moduledoc false

  import Plug.Conn

  alias Gesttalt.Sites

  def init(options), do: options

  def call(%{assigns: %{current_site: site}} = conn, _options) do
    assign(conn, :admin_theme, Sites.get_theme!(site))
  end
end
