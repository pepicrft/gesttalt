defmodule GesttaltWeb.UserRegistrationController do
  use GesttaltWeb, :controller

  alias Gesttalt.AccountRegistrationProtection
  alias Gesttalt.Accounts
  alias Gesttalt.Accounts.User
  alias GesttaltWeb.ClientAddress

  def new(conn, _params) do
    changeset = Accounts.change_user_email(%User{})
    render_registration(conn, changeset)
  end

  def create(conn, %{"user" => user_params} = params) do
    options = protection_options(conn)

    case AccountRegistrationProtection.check(
           user_params["email"],
           ClientAddress.from_conn(conn),
           params["cf-turnstile-response"],
           options
         ) do
      :ok -> register(conn, user_params)
      {:error, :rate_limited, retry_after} -> rate_limited(conn, user_params, retry_after)
      {:error, :verification_failed} -> verification_failed(conn, user_params)
    end
  end

  defp register(conn, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        conn
        |> put_flash(
          :info,
          "We sent a confirmation link to #{user.email}. It expires in 15 minutes."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_registration(conn, changeset)
    end
  end

  defp rate_limited(conn, user_params, retry_after) do
    retry_after_seconds = max(div(retry_after + 999, 1000), 1)

    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
    |> put_flash(:error, "Too many registration attempts. Please try again later.")
    |> render_registration(Accounts.change_user_email(%User{}, user_params))
  end

  defp verification_failed(conn, user_params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_flash(:error, "We could not verify this registration. Please try again.")
    |> render_registration(Accounts.change_user_email(%User{}, user_params))
  end

  defp render_registration(conn, changeset) do
    options = protection_options(conn)

    render(conn, :new,
      changeset: changeset,
      turnstile_site_key: AccountRegistrationProtection.site_key(options),
      turnstile_action: options |> Keyword.fetch!(:turnstile) |> Keyword.fetch!(:action)
    )
  end

  defp protection_options(conn) do
    conn.private[:account_registration_protection] ||
      Application.fetch_env!(:gesttalt, :account_registration_protection)
  end
end
