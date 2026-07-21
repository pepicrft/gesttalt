defmodule Gesttalt.MediaStorage do
  @moduledoc "Storage boundary for publication media."

  alias Gesttalt.Sites.Image

  @callback put(String.t(), binary(), String.t(), keyword()) :: :ok | {:error, term()}
  @callback get(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback delete(String.t(), keyword()) :: :ok | {:error, term()}

  def put(storage_key, body, content_type) do
    adapter().put(storage_key, body, content_type, options())
  end

  def get(storage_key), do: adapter().get(storage_key, options())
  def delete(storage_key), do: adapter().delete(storage_key, options())

  def object_storage?, do: adapter() == Gesttalt.MediaStorage.S3

  def read_legacy(%Image{} = image), do: read_legacy(image.storage_key)

  def read_legacy(storage_key) do
    case legacy_path(storage_key) do
      nil -> {:error, :not_found}
      path -> normalize_file_result(File.read(path))
    end
  end

  def delete_legacy(storage_key) do
    case legacy_path(storage_key) do
      nil ->
        :ok

      path ->
        case File.rm(path) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp adapter, do: Keyword.fetch!(config(), :adapter)
  defp options, do: Keyword.delete(config(), :adapter)

  defp legacy_path(storage_key) do
    case Keyword.get(config(), :legacy_uploads_dir) do
      nil -> nil
      directory -> Path.join(directory, storage_key)
    end
  end

  defp normalize_file_result({:error, :enoent}), do: {:error, :not_found}
  defp normalize_file_result(result), do: result

  defp config, do: Application.fetch_env!(:gesttalt, :media_storage)
end
