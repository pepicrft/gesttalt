defmodule Gesttalt.Retention do
  @moduledoc "Database retention rules enforced by the daily retention worker."

  import Ecto.Query

  alias Boruta.Ecto.{AuthorizationRequest, Token}
  alias Gesttalt.Accounts.{User, UserToken}
  alias Gesttalt.AgentAuth.Registration
  alias Gesttalt.Legal.IllegalContentReport
  alias Gesttalt.Repo

  @day 24 * 60 * 60

  def prune(now \\ DateTime.utc_now(:second)) do
    %{
      user_tokens: prune_user_tokens(now),
      agent_registrations: prune_agent_registrations(now),
      authorization_tokens: prune_authorization_tokens(now),
      authorization_requests: prune_authorization_requests(now),
      legal_reports: prune_legal_reports(now),
      unconfirmed_user_ids: unconfirmed_user_ids(now)
    }
  end

  defp prune_user_tokens(now) do
    session_before = DateTime.add(now, -14 * @day, :second)
    login_before = DateTime.add(now, -15 * 60, :second)
    change_before = DateTime.add(now, -7 * @day, :second)

    UserToken
    |> where(
      [token],
      (token.context == "session" and token.inserted_at < ^session_before) or
        (token.context == "login" and token.inserted_at < ^login_before) or
        (like(token.context, "change:%") and token.inserted_at < ^change_before)
    )
    |> Repo.delete_all()
    |> elem(0)
  end

  defp prune_agent_registrations(now) do
    expired_before = DateTime.add(now, -7 * @day, :second)

    Registration
    |> where(
      [registration],
      registration.status in [:expired, :revoked] and
        registration.updated_at < ^expired_before
    )
    |> or_where(
      [registration],
      registration.status == :pending and registration.expires_at < ^expired_before
    )
    |> Repo.delete_all()
    |> elem(0)
  end

  defp prune_authorization_tokens(now) do
    oldest_allowed = DateTime.add(now, -35 * @day, :second)

    Token
    |> where([token], token.inserted_at < ^oldest_allowed)
    |> Repo.delete_all()
    |> elem(0)
  end

  defp prune_authorization_requests(now) do
    expired_before = DateTime.to_unix(now) - 7 * @day

    AuthorizationRequest
    |> where([request], request.expires_at < ^expired_before)
    |> Repo.delete_all()
    |> elem(0)
  end

  defp prune_legal_reports(now) do
    resolved_before = DateTime.add(now, -3 * 365 * @day, :second)

    IllegalContentReport
    |> where([report], not is_nil(report.resolved_at) and report.resolved_at < ^resolved_before)
    |> Repo.delete_all()
    |> elem(0)
  end

  defp unconfirmed_user_ids(now) do
    inserted_before = DateTime.add(now, -30 * @day, :second)

    User
    |> where([user], is_nil(user.confirmed_at) and user.inserted_at < ^inserted_before)
    |> select([user], user.id)
    |> Repo.all()
  end
end
