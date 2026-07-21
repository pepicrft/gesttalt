defmodule Gesttalt.MediaStorage.S3 do
  @moduledoc false

  @behaviour Gesttalt.MediaStorage

  @impl true
  def put(storage_key, body, content_type, options) do
    options
    |> request()
    |> Req.put(
      url: object_path(storage_key, options),
      headers: [content_type: content_type],
      body: body
    )
    |> successful_write()
  end

  @impl true
  def get(storage_key, options) do
    case Req.get(request(options), url: object_path(storage_key, options), decode_body: false) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:object_storage, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(storage_key, options) do
    case Req.delete(request(options), url: object_path(storage_key, options)) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{status: status}} -> {:error, {:object_storage, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(options) do
    request_options =
      [
        base_url: options |> Keyword.fetch!(:endpoint) |> String.trim_trailing("/"),
        aws_sigv4: [
          access_key_id: Keyword.fetch!(options, :access_key_id),
          secret_access_key: Keyword.fetch!(options, :secret_access_key),
          service: :s3,
          region: Keyword.fetch!(options, :region)
        ]
      ]
      |> Keyword.merge(Keyword.get(options, :request_options, []))

    Req.new(request_options)
  end

  defp object_path(storage_key, options) do
    segments = [Keyword.fetch!(options, :bucket) | String.split(storage_key, "/")]

    "/" <>
      Enum.map_join(segments, "/", fn segment ->
        URI.encode(segment, &URI.char_unreserved?/1)
      end)
  end

  defp successful_write({:ok, %{status: status}}) when status in 200..299, do: :ok
  defp successful_write({:ok, %{status: status}}), do: {:error, {:object_storage, status}}
  defp successful_write({:error, reason}), do: {:error, reason}
end
