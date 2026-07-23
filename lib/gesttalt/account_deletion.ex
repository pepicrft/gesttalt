defmodule Gesttalt.AccountDeletion do
  @moduledoc "Schedules and performs permanent deletion of a Gesttalt account."

  import Ecto.Query

  alias Boruta.Ecto.{Client, Token}
  alias Ecto.Multi
  alias Gesttalt.Accounts.User
  alias Gesttalt.AgentAuth.Registration
  alias Gesttalt.MediaStorage
  alias Gesttalt.Repo
  alias Gesttalt.Sites.{Image, Site}
  alias Gesttalt.Workers.DeleteAccountWorker

  def request(%User{id: user_id}) do
    %{"user_id" => user_id}
    |> DeleteAccountWorker.new()
    |> Oban.insert()
  end

  def delete(user_id, storage \\ MediaStorage)

  def delete(user_id, storage) when is_integer(user_id) and is_atom(storage) do
    case Repo.get(User, user_id) do
      nil ->
        :ok

      %User{} = user ->
        with :ok <- delete_media_objects(user_id, storage),
             {:ok, _changes} <- delete_database_records(user) do
          :ok
        end
    end
  end

  defp delete_media_objects(user_id, storage) do
    Image
    |> join(:inner, [image], site in Site, on: image.site_id == site.id)
    |> where([_image, site], site.user_id == ^user_id)
    |> select([image, _site], image.storage_key)
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn storage_key, :ok ->
      with :ok <- storage.delete(storage_key),
           :ok <- storage.delete_legacy(storage_key) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:media_deletion_failed, storage_key, reason}}}
      end
    end)
  end

  defp delete_database_records(%User{id: user_id} = user) do
    owner_id = to_string(user_id)

    owned_client_ids =
      Client
      |> where([client], fragment("?->>'owner_user_id'", client.metadata) == ^owner_id)
      |> select([client], client.id)
      |> Repo.all()

    Multi.new()
    |> Multi.delete_all(
      :oauth_tokens,
      from(token in Token,
        where: token.sub == ^owner_id or token.client_id in ^owned_client_ids
      )
    )
    |> Multi.delete_all(
      :agent_registrations,
      from(registration in Registration, where: registration.claimed_by_user_id == ^user_id)
    )
    |> Multi.delete_all(
      :oauth_clients,
      from(client in Client, where: client.id in ^owned_client_ids)
    )
    |> Multi.delete(:user, user)
    |> Repo.transaction()
  end
end
