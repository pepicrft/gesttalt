defmodule GesttaltWeb.AgentIdentityController do
  use GesttaltWeb, :controller

  alias Gesttalt.AgentAuth

  def create(conn, %{"type" => "service_auth", "login_hint" => email}) do
    case AgentAuth.create_service_registration(email, remote_ip(conn)) do
      {:ok,
       %{
         registration: registration,
         claim_token: claim_token,
         claim_attempt_token: claim_attempt_token,
         user_code: user_code
       }} ->
        expires_in = DateTime.diff(registration.expires_at, DateTime.utc_now(), :second)

        json(conn, %{
          registration_id: registration.public_id,
          registration_type: "service_auth",
          claim_url: ~p"/agent/identity/claim",
          claim_token: claim_token,
          claim_token_expires: DateTime.to_iso8601(registration.expires_at),
          post_claim_scopes: AgentAuth.scopes(),
          claim: %{
            user_code: user_code,
            expires_in: max(expires_in, 0),
            verification_uri:
              url(~p"/agent/identity/claim?claim_attempt_token=#{claim_attempt_token}"),
            interval: AgentAuth.poll_interval()
          }
        })

      {:error, reason} ->
        identity_error(conn, reason)
    end
  end

  def create(conn, _params), do: identity_error(conn, :unsupported_identity_type)

  defp identity_error(conn, :rate_limited) do
    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("retry-after", "3600")
    |> json(%{error: "rate_limited", error_description: "Try registering again later."})
  end

  defp identity_error(conn, :invalid_login_hint) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "invalid_request",
      error_description: "A valid email login_hint is required."
    })
  end

  defp identity_error(conn, _reason) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "unsupported_identity_type",
      error_description: "Gesttalt currently supports the service_auth identity type."
    })
  end

  defp remote_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      _headers -> format_remote_ip(conn.remote_ip)
    end
  end

  defp format_remote_ip(nil), do: nil
  defp format_remote_ip(address), do: address |> :inet.ntoa() |> to_string()
end
