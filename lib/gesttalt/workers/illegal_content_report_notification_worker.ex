defmodule Gesttalt.Workers.IllegalContentReportNotificationWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 8,
    unique: [period: 7 * 24 * 60 * 60, fields: [:worker, :args]]

  alias Gesttalt.Legal
  alias Gesttalt.Legal.Notifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind, "report_id" => report_id}}) do
    report = Legal.get_illegal_content_report!(report_id)

    case kind do
      "operator" -> Notifier.deliver_operator_notice(report)
      "reporter" -> Notifier.deliver_reporter_acknowledgment(report)
      "decision" -> Notifier.deliver_decision(report)
    end
  end
end
