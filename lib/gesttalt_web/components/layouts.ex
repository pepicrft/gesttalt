defmodule GesttaltWeb.Layouts do
  use GesttaltWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :admin, :boolean, default: false
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header id="app-header">
      <div class="shell" data-part="inner">
        <a data-part="wordmark" href={if(@admin, do: ~p"/admin/", else: ~p"/")}>gesttalt<span data-part="period">.</span></a>
        <nav
          :if={@admin && @current_scope}
          data-part="navigation"
          data-context="admin"
          aria-label={dgettext("navigation", "Publishing")}
        >
          <a href={~p"/admin/"}>{dgettext("navigation", "Content")}</a><a href={
            ~p"/admin/photography"
          }>{dgettext("navigation", "Photography")}</a><a href={~p"/admin/media"}>{dgettext(
            "navigation",
            "Media"
          )}</a><a href={~p"/admin/theme"}>{dgettext("navigation", "Theme")}</a><a href={
            ~p"/admin/settings"
          }>{dgettext("navigation", "Settings")}</a><a href={~p"/admin/oauth-clients"}>{dgettext(
            "navigation",
            "Clients"
          )}</a><a href={~p"/admin/billing"}>
            {if Gesttalt.Plans.early_access?(),
              do: dgettext("navigation", "Access"),
              else: dgettext("navigation", "Billing")}
          </a>
        </nav>
        <nav :if={!@admin} data-part="navigation" data-context="public">
          <a href={~p"/docs"}>{dgettext("navigation", "Developers")}</a><a href={~p"/changelog"}>{dgettext(
            "navigation",
            "Changelog"
          )}</a><a
            :if={!@current_scope || !@current_scope.user}
            href={~p"/users/log-in"}
          >{dgettext("navigation", "Log in")}</a><a
            :if={!@current_scope || !@current_scope.user}
            class="button button--small"
            href={~p"/users/register"}
          >{dgettext("navigation", "Start publishing")}</a><a
            :if={@current_scope && @current_scope.user}
            href={~p"/admin/"}
          >{dgettext("navigation", "Dashboard")}</a>
        </nav>
        <form
          :if={@admin && @current_scope}
          action={~p"/users/log-out"}
          method="post"
          data-part="logout"
        >
          <input type="hidden" name="_method" value="delete" /><input
            type="hidden"
            name="_csrf_token"
            value={get_csrf_token()}
          /><button class="link-button">{dgettext("navigation", "Log out")}</button>
        </form>
      </div>
    </header>
    <main class={["shell", @admin && "dashboard"]}>{render_slot(@inner_block)}</main>
    <.flash_group flash={@flash} />
    <footer id="app-footer">
      <div class="shell" data-part="inner">
        <p data-part="identity">
          gesttalt<span data-part="period">.</span> {dgettext("navigation", "Independent publishing.")}
        </p>
        <nav
          data-part="navigation"
          aria-label={dgettext("navigation", "Legal and service information")}
        >
          <a href={~p"/legal-notice"}>{dgettext("navigation", "Legal notice")}</a><a href={
            ~p"/privacy"
          }>{dgettext("navigation", "Privacy")}</a><a href={~p"/terms"}>{dgettext(
            "navigation",
            "Terms"
          )}</a><a href={~p"/changelog"}>{dgettext(
            "navigation",
            "Changelog"
          )}</a><a href={~p"/withdrawal"}>{dgettext("navigation", "Withdrawal")}</a><a href={
            ~p"/cancel"
          }>{dgettext("navigation", "Cancel contract")}</a><a href={~p"/report-illegal-content"}>{dgettext(
            "navigation",
            "Report illegal content"
          )}</a><a href={~p"/sitemap.xml"}>{dgettext("navigation", "Sitemap")}</a>
        </nav>
      </div>
    </footer>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <div
        :if={message = Phoenix.Flash.get(@flash, :info)}
        data-part="message"
        data-kind="info"
        data-auto-dismiss
      >
        {message}
      </div>
      <div
        :if={message = Phoenix.Flash.get(@flash, :error)}
        data-part="message"
        data-kind="error"
        data-auto-dismiss
      >
        {message}
      </div>
    </div>
    """
  end
end
