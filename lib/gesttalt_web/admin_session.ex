defmodule GesttaltWeb.AdminSession do
  @moduledoc false

  alias Gesttalt.Sites

  @state_bytes 32
  @max_return_to_bytes 2_048

  def generate_state,
    do: @state_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def valid_state?(state) when is_binary(state) do
    case Base.url_decode64(state, padding: false) do
      {:ok, decoded} -> byte_size(decoded) == @state_bytes
      :error -> false
    end
  end

  def valid_state?(_state), do: false

  def return_to(conn) do
    suffix = if conn.query_string == "", do: "", else: "?#{conn.query_string}"
    safe_return_to(conn.request_path <> suffix)
  end

  def safe_return_to(value) when is_binary(value) and byte_size(value) <= @max_return_to_bytes do
    case URI.parse(value) do
      %URI{scheme: nil, host: nil, fragment: nil, path: path} = uri ->
        if admin_path?(path), do: URI.to_string(uri), else: "/admin/"

      _uri ->
        "/admin/"
    end
  end

  def safe_return_to(_value), do: "/admin/"

  def external_url(hostname, path) do
    endpoint_url = GesttaltWeb.Endpoint.config(:url)
    scheme = Keyword.get(endpoint_url, :scheme, "https")
    port = Keyword.get(endpoint_url, :port, default_port(scheme))
    relative = URI.parse(path)

    %URI{
      scheme: scheme,
      host: hostname,
      port: normalized_port(scheme, port),
      path: relative.path,
      query: relative.query
    }
    |> URI.to_string()
  end

  def platform_start_url(hostname, state, return_to) do
    query = URI.encode_query(%{"host" => hostname, "return_to" => return_to, "state" => state})
    external_url(Sites.platform_host(), "/admin/session/start?#{query}")
  end

  def completion_url(hostname, token, return_to) do
    query = URI.encode_query(%{"return_to" => return_to})
    external_url(hostname, "/admin/session/complete/#{token}?#{query}")
  end

  defp admin_path?("/admin"), do: true

  defp admin_path?("/admin/" <> rest),
    do: rest != "session" and not String.starts_with?(rest, "session/")

  defp admin_path?(_path), do: false

  defp default_port("http"), do: 80
  defp default_port("https"), do: 443

  defp normalized_port("http", 80), do: nil
  defp normalized_port("https", 443), do: nil
  defp normalized_port(_scheme, port), do: port
end
