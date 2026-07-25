defmodule Gesttalt.OpenGraph.Signer do
  @moduledoc """
  Signs and verifies the query parameters carried by Open Graph image URLs.

  Every Open Graph image URL that Gesttalt renders into a page carries a
  `sig` parameter. The signature is a keyed-hash message authentication code
  (see https://www.rfc-editor.org/rfc/rfc2104) over the remaining parameters,
  so the image endpoint only ever renders requests that Gesttalt itself minted.
  This closes off a headless-browser denial-of-service vector where an attacker
  could otherwise trigger expensive renders with arbitrary parameters.

  Signatures are stable (they carry no timestamp) so the resulting URLs stay
  cacheable by content delivery networks and remain valid when a social crawler
  fetches them long after the page was rendered.
  """

  alias Plug.Crypto.KeyGenerator

  @salt "gesttalt-og-image"

  @doc "Returns the signature for the given parameter map."
  @spec sign(map(), binary()) :: String.t()
  def sign(params, secret) when is_map(params) and is_binary(secret) do
    :hmac
    |> :crypto.mac(:sha256, derive_key(secret), canonical(params))
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Verifies a signature against the given parameters using a constant-time compare.

  The `sig` key is ignored when present in `params`, so the full incoming query
  map can be passed directly.
  """
  @spec valid?(map(), term(), binary()) :: boolean()
  def valid?(params, signature, secret)
      when is_map(params) and is_binary(signature) and is_binary(secret) do
    expected = sign(Map.delete(params, "sig"), secret)
    Plug.Crypto.secure_compare(expected, signature)
  end

  def valid?(_params, _signature, _secret), do: false

  defp canonical(params) do
    params
    |> Map.delete("sig")
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp derive_key(secret), do: KeyGenerator.generate(secret, @salt)
end
