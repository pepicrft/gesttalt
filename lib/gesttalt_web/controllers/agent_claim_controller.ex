defmodule GesttaltWeb.AgentClaimController do
  use GesttaltWeb, :controller

  alias Gesttalt.Accounts
  alias Gesttalt.AgentAuth

  def show(conn, %{"claim_attempt_token" => token}) do
    case AgentAuth.get_claim_attempt(token) do
      {:ok, registration} ->
        case current_user(conn) do
          nil -> prepare_sign_in(conn, registration, token)
          user -> render_claim(conn, registration, token, user)
        end

      {:error, reason} ->
        render_claim_error(conn, reason)
    end
  end

  def show(conn, _params), do: render_claim_error(conn, :invalid_claim_token)

  def update(conn, %{"claim_attempt_token" => token, "user_code" => user_code}) do
    case AgentAuth.confirm_claim(token, user_code, current_user(conn)) do
      {:ok, registration} ->
        render(conn, :show,
          page_title: dgettext("agent_auth", "Agent access confirmed"),
          registration: registration,
          claim_attempt_token: token,
          confirmed: true
        )

      {:error, reason} ->
        case AgentAuth.get_claim_attempt(token) do
          {:ok, registration} ->
            conn
            |> put_status(claim_error_status(reason))
            |> put_flash(:error, claim_error_message(reason))
            |> render(:show,
              page_title: dgettext("agent_auth", "Confirm agent access"),
              registration: registration,
              claim_attempt_token: token,
              confirmed: false
            )

          _error ->
            render_claim_error(conn, reason)
        end
    end
  end

  def update(conn, _params), do: render_claim_error(conn, :invalid_request)

  defp prepare_sign_in(conn, registration, token) do
    return_to = ~p"/agent/identity/claim?claim_attempt_token=#{token}"

    case AgentAuth.ensure_claim_user(registration) do
      {:ok, user, :created} ->
        {:ok, _email} =
          Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        conn
        |> put_session(:user_return_to, return_to)
        |> put_flash(
          :info,
          dgettext(
            "agent_auth",
            "We created your Gesttalt account. Open the sign-in link sent to your email, then confirm the code shown by your agent."
          )
        )
        |> redirect(to: ~p"/users/log-in?email=#{user.email}")

      {:ok, user, :existing} ->
        conn
        |> put_session(:user_return_to, return_to)
        |> put_flash(
          :info,
          dgettext("agent_auth", "Sign in, then confirm the code shown by your agent.")
        )
        |> redirect(to: ~p"/users/log-in?email=#{user.email}")

      {:error, _reason} ->
        render_claim_error(conn, :account_unavailable)
    end
  end

  defp render_claim(conn, registration, token, user) do
    if user.email == registration.claim_email do
      render(conn, :show,
        page_title: dgettext("agent_auth", "Confirm agent access"),
        registration: registration,
        claim_attempt_token: token,
        confirmed: registration.status == :claimed
      )
    else
      render_claim_error(conn, :account_mismatch)
    end
  end

  defp render_claim_error(conn, reason) do
    conn
    |> put_status(claim_error_status(reason))
    |> render(:error,
      page_title: dgettext("agent_auth", "Agent access unavailable"),
      message: claim_error_message(reason)
    )
  end

  defp claim_error_status(:account_mismatch), do: :forbidden
  defp claim_error_status(:invalid_user_code), do: :unprocessable_entity
  defp claim_error_status(_reason), do: :not_found

  defp claim_error_message(:account_mismatch),
    do:
      dgettext(
        "agent_auth",
        "This request belongs to a different email address. Sign out and use the requested account."
      )

  defp claim_error_message(:invalid_user_code),
    do:
      dgettext(
        "agent_auth",
        "That code does not match. Check the six digits shown by your agent."
      )

  defp claim_error_message(:already_claimed),
    do: dgettext("agent_auth", "This request has already been confirmed.")

  defp claim_error_message(_reason),
    do: dgettext("agent_auth", "This agent access request is invalid or has expired.")

  defp current_user(conn), do: get_in(conn.assigns, [:current_scope, Access.key(:user)])
end
