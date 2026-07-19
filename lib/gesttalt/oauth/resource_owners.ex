defmodule Gesttalt.OAuth.ResourceOwners do
  @moduledoc false

  @behaviour Boruta.Oauth.ResourceOwners

  import Ecto.Query

  alias Boruta.Ecto.Scope
  alias Boruta.Oauth.ResourceOwner
  alias Gesttalt.Accounts.User
  alias Gesttalt.Repo

  @impl true
  def get_by(username: username), do: resource_owner(Repo.get_by(User, email: username))

  def get_by(attrs) do
    attrs |> Keyword.fetch!(:sub) |> then(&Repo.get(User, &1)) |> resource_owner()
  end

  @impl true
  def check_password(%ResourceOwner{sub: sub}, password) do
    if User.valid_password?(Repo.get(User, sub), password),
      do: :ok,
      else: {:error, "Invalid email or password."}
  end

  @impl true
  def authorized_scopes(%ResourceOwner{}) do
    Repo.all(from scope in Scope, order_by: [asc: scope.name])
  end

  @impl true
  def claims(%ResourceOwner{username: email}, _scope), do: %{email: email}

  defp resource_owner(%User{id: id, email: email}) do
    {:ok, %ResourceOwner{sub: to_string(id), username: email}}
  end

  defp resource_owner(nil), do: {:error, "User not found."}
end
