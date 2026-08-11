defmodule Gesttalt.MediaStorage.Local do
  @moduledoc false

  @behaviour Gesttalt.MediaStorage

  @impl true
  def put(storage_key, body, _content_type, options) do
    destination = path(storage_key, options)
    File.mkdir_p!(Path.dirname(destination))
    File.write(destination, body)
  end

  @impl true
  def get(storage_key, options) do
    case File.read(path(storage_key, options)) do
      {:error, :enoent} -> {:error, :not_found}
      result -> result
    end
  end

  @impl true
  def delete(storage_key, options) do
    case File.rm(path(storage_key, options)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp path(storage_key, options) do
    options |> Keyword.fetch!(:uploads_dir) |> Path.join(storage_key)
  end
end
