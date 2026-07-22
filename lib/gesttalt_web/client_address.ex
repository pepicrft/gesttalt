defmodule GesttaltWeb.ClientAddress do
  @moduledoc "Extracts the client network address forwarded by Gesttalt's trusted Caddy proxy."

  import Plug.Conn, only: [get_req_header: 2]

  @spec from_conn(Plug.Conn.t()) :: String.t() | nil
  def from_conn(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      _headers -> format(conn.remote_ip)
    end
  end

  defp format(nil), do: nil
  defp format(address), do: address |> :inet.ntoa() |> to_string()
end
