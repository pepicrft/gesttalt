defmodule Gesttalt.Workers.RetentionWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :retention,
    max_attempts: 8,
    unique: [period: 23 * 60 * 60, fields: [:worker]]

  alias Gesttalt.AccountDeletion
  alias Gesttalt.Retention

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Retention.prune()
    |> Map.fetch!(:unconfirmed_user_ids)
    |> Enum.reduce_while(:ok, fn user_id, :ok ->
      case AccountDeletion.delete(user_id) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
