defmodule Gesttalt.RetentionTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.Accounts
  alias Gesttalt.Accounts.UserToken
  alias Gesttalt.Legal.IllegalContentReport
  alias Gesttalt.Repo
  alias Gesttalt.Retention

  import Gesttalt.AccountsFixtures

  @day 24 * 60 * 60

  test "removes expired account tokens and resolved legal reports" do
    now = ~U[2026-07-23 12:00:00Z]
    user = user_fixture()

    expired_session =
      Repo.insert!(%UserToken{
        user_id: user.id,
        token: :crypto.strong_rand_bytes(32),
        context: "session",
        inserted_at: DateTime.add(now, -15 * @day, :second)
      })

    current_session =
      Repo.insert!(%UserToken{
        user_id: user.id,
        token: :crypto.strong_rand_bytes(32),
        context: "session",
        inserted_at: DateTime.add(now, -13 * @day, :second)
      })

    expired_report =
      Repo.insert!(%IllegalContentReport{
        reference: "G-expired",
        content_url: "https://example.com/old",
        explanation: "A resolved report retained for the required review period.",
        good_faith: true,
        status: :resolved,
        decision: "The content was assessed and the report was resolved.",
        resolved_at: DateTime.add(now, -3 * 365 * @day - @day, :second)
      })

    current_report =
      Repo.insert!(%IllegalContentReport{
        reference: "G-current",
        content_url: "https://example.com/current",
        explanation: "A resolved report still within the required review period.",
        good_faith: true,
        status: :resolved,
        decision: "The content was assessed and the report was resolved.",
        resolved_at: DateTime.add(now, -2 * 365 * @day, :second)
      })

    result = Retention.prune(now)

    assert result.user_tokens == 1
    assert result.legal_reports == 1
    refute Repo.get(UserToken, expired_session.id)
    assert Repo.get(UserToken, current_session.id)
    refute Repo.get(IllegalContentReport, expired_report.id)
    assert Repo.get(IllegalContentReport, current_report.id)
  end

  test "identifies unconfirmed accounts after 30 days for complete deletion" do
    now = ~U[2026-07-23 12:00:00Z]
    {:ok, stale_user} = Accounts.register_user(%{email: unique_user_email()})
    {:ok, current_user} = Accounts.register_user(%{email: unique_user_email()})

    Repo.update_all(
      from(user in Gesttalt.Accounts.User, where: user.id == ^stale_user.id),
      set: [inserted_at: DateTime.add(now, -31 * @day, :second)]
    )

    result = Retention.prune(now)

    assert stale_user.id in result.unconfirmed_user_ids
    refute current_user.id in result.unconfirmed_user_ids
  end
end
