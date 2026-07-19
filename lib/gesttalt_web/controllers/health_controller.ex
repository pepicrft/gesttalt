defmodule GesttaltWeb.HealthController do
  use GesttaltWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
