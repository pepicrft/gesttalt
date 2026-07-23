defmodule Gesttalt.Legal.Notifier do
  @moduledoc false

  import Swoosh.Email

  alias Gesttalt.Legal.IllegalContentReport
  alias Gesttalt.Mailer

  @contact {"Gesttalt", "gesttalt@pepicrft.me"}

  def deliver_operator_notice(%IllegalContentReport{} = report) do
    body = """
    A new illegal-content report has been received.

    Reference: #{report.reference}
    Content address: #{report.content_url}
    Reporter: #{report.reporter_name || "Not provided under the sensitive-offence exception"}
    Reporter email: #{report.reporter_email || "Not provided under the sensitive-offence exception"}

    Explanation:
    #{report.explanation}

    The reporter confirmed that the information is accurate and complete to the best of their knowledge and belief.
    """

    deliver(@contact, "Illegal-content report #{report.reference}", body)
  end

  def deliver_reporter_acknowledgment(%IllegalContentReport{reporter_email: email} = report)
      when is_binary(email) do
    body = """
    Gesttalt received your illegal-content report.

    Reference: #{report.reference}
    Content address: #{report.content_url}

    The report will be assessed diligently, objectively, and by a person. You may reply to this message with more information. Gesttalt will send a decision notice to this address when the assessment is complete, unless the law prevents disclosure.

    This mailbox is not an emergency service. Contact the appropriate emergency or law-enforcement service if someone is in immediate danger.
    """

    deliver(email, "Gesttalt received report #{report.reference}", body)
  end

  def deliver_decision(%IllegalContentReport{reporter_email: email} = report)
      when is_binary(email) do
    body = """
    Gesttalt completed its assessment of your illegal-content report.

    Reference: #{report.reference}
    Content address: #{report.content_url}

    Decision:
    #{report.decision}

    You may reply to this message to request a human review or provide material information that was not available during the assessment.
    """

    deliver(email, "Decision for Gesttalt report #{report.reference}", body)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(@contact)
      |> reply_to(@contact)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
