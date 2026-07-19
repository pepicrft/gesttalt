defmodule GesttaltWeb.PageController do
  use GesttaltWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      page_title: dgettext("marketing", "A simple blogging platform for the agentic world"),
      meta_description:
        dgettext(
          "marketing",
          "Publish from the web, an application, an automation, or an agent."
        )
    )
  end

  def docs(conn, _params) do
    render(conn, :docs,
      page_title: "Publish from anywhere",
      meta_description: "Gesttalt publishing interfaces and Model Context Protocol tools."
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
    render(conn, :report_illegal_content,
      page_title: dgettext("legal", "Report illegal content"),
      meta_description:
        dgettext(
          "legal",
          "Report specific content that may be illegal on a Gesttalt publication."
        )
    )
  end
end
