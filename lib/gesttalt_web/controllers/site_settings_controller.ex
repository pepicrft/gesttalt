defmodule GesttaltWeb.SiteSettingsController do
  use GesttaltWeb, :controller

  alias Gesttalt.Sites
  alias Gesttalt.Sites.{Domain, Site}

  def show(conn, _params) do
    site = current_site(conn)

    render(conn, :show,
      page_title: "Publication settings",
      site: site,
      domains: Sites.list_domains(site),
      custom_domain_target: Sites.custom_domain_target(),
      site_changeset: Site.changeset(site, %{}),
      domain_changeset: Domain.changeset(%Domain{}, %{})
    )
  end

  def update(conn, %{"site" => attrs}) do
    case Sites.update_site(current_site(conn), attrs) do
      {:ok, _site} ->
        conn |> put_flash(:info, "Publication updated.") |> redirect(to: ~p"/admin/settings")

      {:error, changeset} ->
        render(conn, :show,
          page_title: "Publication settings",
          site: current_site(conn),
          domains: Sites.list_domains(current_site(conn)),
          custom_domain_target: Sites.custom_domain_target(),
          site_changeset: changeset,
          domain_changeset: Domain.changeset(%Domain{}, %{})
        )
    end
  end

  def create_domain(conn, %{"domain" => attrs}) do
    site = current_site(conn)

    case Sites.add_custom_domain(site, attrs) do
      {:ok, _domain} ->
        conn
        |> put_flash(:info, "Domain added. Add the ownership and routing records shown below.")
        |> redirect(to: ~p"/admin/settings")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Domain could not be added: #{inspect(reason)}")
        |> redirect(to: ~p"/admin/settings")
    end
  end

  def verify_domain(conn, %{"id" => id}) do
    case Sites.verify_domain(current_site(conn), id) do
      {:ok, _domain} ->
        conn
        |> put_flash(:info, "Domain ownership and routing verified. The domain is active.")
        |> redirect(to: ~p"/admin/settings")

      {:error, :verification_record_not_found} ->
        conn
        |> put_flash(:error, "The verification record was not found yet.")
        |> redirect(to: ~p"/admin/settings")

      {:error, :routing_record_not_found} ->
        conn
        |> put_flash(:error, "The domain does not point to Gesttalt yet.")
        |> redirect(to: ~p"/admin/settings")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Domain could not be verified: #{inspect(reason)}")
        |> redirect(to: ~p"/admin/settings")
    end
  end

  def delete_domain(conn, %{"id" => id}) do
    Sites.delete_domain(current_site(conn), id)
    conn |> put_flash(:info, "Domain removed.") |> redirect(to: ~p"/admin/settings")
  end

  defp current_site(conn) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    site
  end
end
