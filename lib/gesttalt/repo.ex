defmodule Gesttalt.Repo do
  use Ecto.Repo,
    otp_app: :gesttalt,
    adapter: Ecto.Adapters.Postgres
end
