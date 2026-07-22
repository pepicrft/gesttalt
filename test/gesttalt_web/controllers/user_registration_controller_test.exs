defmodule GesttaltWeb.UserRegistrationControllerTest do
  use GesttaltWeb.ConnCase, async: true

  import Gesttalt.AccountsFixtures

  alias Gesttalt.Accounts

  defmodule RateLimiter do
    def hit(key, _period, _limit) do
      send(self(), {:rate_limit_checked, key})

      case Process.get({__MODULE__, :result}, {:allow, 1}) do
        result when is_function(result, 1) -> result.(key)
        result -> result
      end
    end
  end

  defmodule TurnstileVerifier do
    def verify(token, options) do
      send(self(), {:turnstile_verified, token, options})
      Process.get({__MODULE__, :result}, :ok)
    end
  end

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ ~p"/users/log-in"
      assert response =~ ~p"/users/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/admin/"
    end

    test "renders Cloudflare Turnstile when registration protection is enabled", %{conn: conn} do
      conn = conn |> with_registration_protection() |> get(~p"/users/register")

      response = html_response(conn, 200)
      assert response =~ "cf-turnstile"
      assert response =~ "test-site-key"
      assert response =~ "account_registration"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account but does not log in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"

      assert conn.assigns.flash["info"] ==
               "We sent a confirmation link to #{email}. It expires in 15 minutes."
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
    end

    test "checks rate limits and Turnstile before creating an account", %{conn: conn} do
      email = unique_user_email()

      conn =
        conn
        |> with_registration_protection()
        |> put_req_header("x-forwarded-for", "203.0.113.8")
        |> post(~p"/users/register", %{
          "user" => valid_user_attributes(email: email),
          "cf-turnstile-response" => "verified-token"
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert_receive {:rate_limit_checked,
                      {:account_registration, :client_address, "203.0.113.8"}}

      assert_receive {:turnstile_verified, "verified-token", turnstile_options}
      assert turnstile_options[:client_address] == "203.0.113.8"
      assert turnstile_options[:expected_hostname] == "gesttalt.test"

      assert_receive {:rate_limit_checked, {:account_registration, :email, email_digest}}
      assert is_binary(email_digest)
    end

    test "rejects a failed Turnstile verification without creating an account", %{conn: conn} do
      email = unique_user_email()
      Process.put({TurnstileVerifier, :result}, {:error, :rejected})

      conn =
        conn
        |> with_registration_protection()
        |> post(~p"/users/register", %{
          "user" => valid_user_attributes(email: email),
          "cf-turnstile-response" => "rejected-token"
        })

      response = html_response(conn, 422)
      assert response =~ "We could not verify this registration. Please try again."
      refute_received {:rate_limit_checked, {:account_registration, :email, _digest}}
      assert Accounts.get_user_by_email(email) == nil
    end

    test "rejects an address over the local registration limit", %{conn: conn} do
      email = unique_user_email()
      Process.put({RateLimiter, :result}, {:deny, 90_000})

      conn =
        conn
        |> with_registration_protection()
        |> post(~p"/users/register", %{
          "user" => valid_user_attributes(email: email),
          "cf-turnstile-response" => "unused-token"
        })

      response = html_response(conn, 429)
      assert response =~ "Too many registration attempts. Please try again later."
      assert get_resp_header(conn, "retry-after") == ["90"]
      refute_received {:turnstile_verified, _token, _options}
      assert Accounts.get_user_by_email(email) == nil
    end

    test "checks a verified email against its local registration limit", %{conn: conn} do
      email = unique_user_email()

      Process.put({RateLimiter, :result}, fn
        {:account_registration, :email, _digest} -> {:deny, 30_000}
        _key -> {:allow, 1}
      end)

      conn =
        conn
        |> with_registration_protection()
        |> post(~p"/users/register", %{
          "user" => valid_user_attributes(email: email),
          "cf-turnstile-response" => "verified-token"
        })

      response = html_response(conn, 429)
      assert response =~ "Too many registration attempts. Please try again later."
      assert_received {:turnstile_verified, "verified-token", _options}
      assert Accounts.get_user_by_email(email) == nil
    end
  end

  defp with_registration_protection(conn) do
    put_private(conn, :account_registration_protection,
      enabled: true,
      rate_limiter: RateLimiter,
      turnstile_verifier: TurnstileVerifier,
      rate_limit: [period: :timer.hours(1), per_client_address: 5, per_email: 3],
      turnstile: [
        site_key: "test-site-key",
        secret_key: "test-secret-key",
        hostname: "gesttalt.test",
        action: "account_registration"
      ]
    )
  end
end
