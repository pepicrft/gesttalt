defmodule GesttaltWeb.BillingController do
  use GesttaltWeb, :controller

  alias Gesttalt.Billing
  alias Gesttalt.Plans
  alias Gesttalt.Sites

  def show(conn, params) do
    site = current_site(conn)

    render(conn, :show,
      page_title: dgettext("billing", "Billing"),
      site: site,
      plan: Plans.tier(site),
      price: Billing.monthly_price_euros(),
      billing_configured: Billing.configured?(),
      free_features: [
        dgettext("billing", "Unlimited posts and pages"),
        dgettext("billing", "A gesttalt.org subdomain"),
        dgettext("billing", "The Paper theme"),
        dgettext("billing", "Web, application, agent, and feed publishing")
      ],
      publisher_features: [
        dgettext("billing", "Everything in Free"),
        dgettext("billing", "Custom domains"),
        dgettext("billing", "Image and file uploads"),
        dgettext("billing", "Custom Liquid themes")
      ],
      checkout: params["checkout"]
    )
  end

  def checkout(conn, _params) do
    site = current_site(conn)

    if Plans.publisher?(site) do
      conn
      |> put_flash(:info, dgettext("billing", "The Publisher plan is already active."))
      |> redirect(to: ~p"/admin/billing")
    else
      case Billing.checkout_url(
             site,
             conn.assigns.current_scope.user.email,
             url(~p"/admin/billing")
           ) do
        {:ok, checkout_url} ->
          redirect(conn, external: checkout_url)

        {:error, reason} ->
          conn
          |> put_flash(
            :error,
            dgettext("billing", "Billing is not available: %{reason}", reason: inspect(reason))
          )
          |> redirect(to: ~p"/admin/billing")
      end
    end
  end

  def portal(conn, _params) do
    case Billing.portal_url(current_site(conn), url(~p"/admin/billing")) do
      {:ok, portal_url} ->
        redirect(conn, external: portal_url)

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          dgettext("billing", "The billing portal is not available: %{reason}",
            reason: inspect(reason)
          )
        )
        |> redirect(to: ~p"/admin/billing")
    end
  end

  def webhook(conn, _params) do
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    case Billing.process_webhook(conn.assigns[:raw_body] || "", signature) do
      {:error, _reason} -> send_resp(conn, 400, "invalid webhook")
      _result -> send_resp(conn, 200, "ok")
    end
  end

  defp current_site(conn) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    site
  end
end
