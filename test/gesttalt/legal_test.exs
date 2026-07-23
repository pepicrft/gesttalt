defmodule Gesttalt.LegalTest do
  use Gesttalt.DataCase, async: true
  use Oban.Testing, repo: Gesttalt.Repo

  alias Gesttalt.Legal
  alias Gesttalt.Workers.IllegalContentReportNotificationWorker

  @valid_attrs %{
    content_url: "https://writer.gesttalt.test/blog/reported-post",
    explanation:
      "This page contains a specific threat against an identified person and should be reviewed.",
    reporter_name: "Robin Reporter",
    reporter_email: "reporter@example.com",
    good_faith: true
  }

  test "creates a report and queues operator and reporter notices" do
    assert {:ok, report} = Legal.create_illegal_content_report(@valid_attrs)
    assert report.reference =~ "G-"
    assert report.status == :received

    assert_enqueued(
      worker: IllegalContentReportNotificationWorker,
      args: %{"kind" => "operator", "report_id" => report.id}
    )

    assert_enqueued(
      worker: IllegalContentReportNotificationWorker,
      args: %{"kind" => "reporter", "report_id" => report.id}
    )
  end

  test "requires contact details for an ordinary report" do
    changeset =
      Legal.change_illegal_content_report(
        Map.drop(@valid_attrs, [:reporter_name, :reporter_email])
      )

    refute changeset.valid?

    assert "is required unless the report concerns suspected child sexual abuse or exploitation" in errors_on(
             changeset
           ).reporter_name
  end

  test "allows the statutory sensitive-offence exception without contact details" do
    attrs =
      @valid_attrs
      |> Map.drop([:reporter_name, :reporter_email])
      |> Map.put(:anonymous_sensitive_offence, true)

    assert {:ok, report} = Legal.create_illegal_content_report(attrs)
    assert report.reporter_email == nil

    assert_enqueued(
      worker: IllegalContentReportNotificationWorker,
      args: %{"kind" => "operator", "report_id" => report.id}
    )

    refute_enqueued(
      worker: IllegalContentReportNotificationWorker,
      args: %{"kind" => "reporter", "report_id" => report.id}
    )
  end

  test "requires a complete web address, an explanation, and the good-faith statement" do
    changeset =
      Legal.change_illegal_content_report(%{
        @valid_attrs
        | content_url: "/relative",
          explanation: "Too short",
          good_faith: false
      })

    refute changeset.valid?
    assert "must be a complete http or https address" in errors_on(changeset).content_url
    assert "should be at least 20 character(s)" in errors_on(changeset).explanation

    assert "must be confirmed before the report can be submitted" in errors_on(changeset).good_faith
  end
end
