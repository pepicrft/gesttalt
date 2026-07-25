defmodule GesttaltWeb.PageController do
  use GesttaltWeb, :controller

  alias Gesttalt.Changelog
  alias Gesttalt.IllegalContentReportProtection
  alias Gesttalt.Legal
  alias GesttaltWeb.ClientAddress

  def home(conn, _params) do
    render(conn, :home,
      page_title: dgettext("marketing", "A blog your agents can run"),
      meta_description:
        dgettext(
          "marketing",
          "Agent-native publishing for content, media, themes, domains, and the complete publication."
        )
    )
  end

  def docs(conn, _params) do
    render(conn, :docs,
      page_title: "Publish from anywhere",
      meta_description: "Gesttalt publishing interfaces and Model Context Protocol tools."
    )
  end

  def changelog(conn, _params) do
    render(conn, :changelog,
      page_title: "Changelog",
      meta_description: "New Gesttalt capabilities, improvements, and other product updates.",
      entries: Changelog.list(),
      rss_feed_path: ~p"/changelog/feed.xml",
      atom_feed_path: ~p"/changelog/atom.xml"
    )
  end

  def legal_notice(conn, _params) do
    render(conn, :legal_notice,
      page_title: dgettext("legal", "Legal notice"),
      meta_description: dgettext("legal", "Provider and contact information for Gesttalt.")
    )
  end

  def privacy(conn, _params) do
    render(conn, :privacy,
      page_title: dgettext("legal", "Privacy policy"),
      meta_description: dgettext("legal", "How Gesttalt handles personal information.")
    )
  end

  def terms(conn, _params) do
    render(conn, :terms,
      page_title: dgettext("legal", "Terms of service"),
      meta_description:
        dgettext("legal", "The terms that govern use of the Gesttalt publishing platform.")
    )
  end

  def withdrawal(conn, _params) do
    render(conn, :withdrawal,
      page_title: dgettext("legal", "Right of withdrawal"),
      meta_description:
        dgettext(
          "legal",
          "Information about withdrawing from a recent Gesttalt consumer contract."
        )
    )
  end

  def cancel(conn, _params) do
    render(conn, :cancel,
      page_title: dgettext("legal", "Cancel a subscription"),
      meta_description: dgettext("legal", "End an ongoing Gesttalt subscription.")
    )
  end

  def report_illegal_content(conn, _params) do
    render_illegal_content_report(conn, Legal.change_illegal_content_report())
  end

  def create_illegal_content_report(conn, %{"illegal_content_report" => report_params} = params) do
    options = illegal_content_report_protection_options(conn)

    case IllegalContentReportProtection.check(
           ClientAddress.from_conn(conn),
           params["cf-turnstile-response"],
           options
         ) do
      :ok ->
        persist_illegal_content_report(conn, report_params)

      {:error, :rate_limited, retry_after} ->
        retry_after_seconds = max(div(retry_after + 999, 1000), 1)

        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
        |> put_flash(:error, dgettext("legal", "Too many reports. Please try again later."))
        |> render_illegal_content_report(Legal.change_illegal_content_report(report_params))

      {:error, :verification_failed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(
          :error,
          dgettext("legal", "The security check could not be verified. Please try again.")
        )
        |> render_illegal_content_report(Legal.change_illegal_content_report(report_params))
    end
  end

  defp persist_illegal_content_report(conn, report_params) do
    case Legal.create_illegal_content_report(report_params) do
      {:ok, report} ->
        conn
        |> put_flash(
          :info,
          dgettext(
            "legal",
            "Your report was received. Keep reference %{reference} for follow-up.",
            reference: report.reference
          )
        )
        |> redirect(to: ~p"/report-illegal-content")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_illegal_content_report(changeset)

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> put_flash(
          :error,
          dgettext(
            "legal",
            "The report could not be recorded. Please email gesttalt@pepicrft.me."
          )
        )
        |> render_illegal_content_report(Legal.change_illegal_content_report(report_params))
    end
  end

  defp render_illegal_content_report(conn, changeset) do
    options = illegal_content_report_protection_options(conn)

    render(conn, :report_illegal_content,
      page_title: dgettext("legal", "Report illegal content"),
      meta_description:
        dgettext(
          "legal",
          "Report specific content that may be illegal on a Gesttalt publication."
        ),
      changeset: changeset,
      turnstile_site_key: IllegalContentReportProtection.site_key(options),
      turnstile_action: options |> Keyword.fetch!(:turnstile) |> Keyword.fetch!(:action)
    )
  end

  defp illegal_content_report_protection_options(conn) do
    conn.private[:illegal_content_report_protection] ||
      Application.fetch_env!(:gesttalt, :illegal_content_report_protection)
  end
end
