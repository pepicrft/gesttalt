defmodule Gesttalt.Workers.DeleteAccountWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :retention,
    max_attempts: 12,
    unique: [period: 30 * 24 * 60 * 60, fields: [:worker, :args]]

  alias Gesttalt.AccountDeletion

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    AccountDeletion.delete(user_id)
  end
end
