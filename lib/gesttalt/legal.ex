defmodule Gesttalt.Legal do
  @moduledoc "Compliance records and public legal-reporting workflows."

  alias Ecto.Multi
  alias Gesttalt.Legal.IllegalContentReport
  alias Gesttalt.Repo
  alias Gesttalt.Workers.IllegalContentReportNotificationWorker

  def change_illegal_content_report(attrs \\ %{}) do
    IllegalContentReport.create_changeset(attrs)
  end

  def create_illegal_content_report(attrs) do
    Multi.new()
    |> Multi.insert(:report, IllegalContentReport.create_changeset(attrs))
    |> Multi.run(:notification_jobs, fn _repo, %{report: report} ->
      enqueue_notifications(report)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{report: report}} -> {:ok, report}
      {:error, :report, changeset, _changes} -> {:error, changeset}
      {:error, :notification_jobs, reason, _changes} -> {:error, reason}
    end
  end

  def get_illegal_content_report!(id), do: Repo.get!(IllegalContentReport, id)

  def resolve_illegal_content_report(report, decision, resolved_at \\ DateTime.utc_now(:second)) do
    Multi.new()
    |> Multi.update(
      :report,
      IllegalContentReport.resolve_changeset(report, decision, resolved_at)
    )
    |> Multi.run(:decision_notification, fn _repo, %{report: resolved_report} ->
      enqueue_decision_notification(resolved_report)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{report: resolved_report}} -> {:ok, resolved_report}
      {:error, :report, changeset, _changes} -> {:error, changeset}
      {:error, :decision_notification, reason, _changes} -> {:error, reason}
    end
  end

  defp enqueue_notifications(report) do
    jobs =
      [
        IllegalContentReportNotificationWorker.new(%{
          "kind" => "operator",
          "report_id" => report.id
        })
      ] ++
        if report.reporter_email do
          [
            IllegalContentReportNotificationWorker.new(%{
              "kind" => "reporter",
              "report_id" => report.id
            })
          ]
        else
          []
        end

    Enum.reduce_while(jobs, {:ok, []}, fn job, {:ok, inserted} ->
      case Oban.insert(job) do
        {:ok, inserted_job} -> {:cont, {:ok, [inserted_job | inserted]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp enqueue_decision_notification(%{reporter_email: nil}), do: {:ok, :not_requested}

  defp enqueue_decision_notification(report) do
    report
    |> then(
      &IllegalContentReportNotificationWorker.new(%{
        "kind" => "decision",
        "report_id" => &1.id
      })
    )
    |> Oban.insert()
  end
end
