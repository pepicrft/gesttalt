defmodule GesttaltWeb.OAuth.TokenController do
  @behaviour Boruta.Oauth.TokenApplication

  use GesttaltWeb, :controller

  alias Boruta.Oauth.{Error, TokenResponse}
  alias Gesttalt.AgentAuth

  @claim_grant "urn:workos:agent-auth:grant-type:claim"
  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"

  def token(conn, %{"grant_type" => grant_type, "claim_token" => claim_token})
      when grant_type == @claim_grant do
    case AgentAuth.exchange_claim(claim_token) do
      {:ok, response} -> agent_token_success(conn, response)
      {:error, reason} -> agent_token_error(conn, reason)
    end
  end

  def token(conn, %{"grant_type" => grant_type, "assertion" => assertion} = params)
      when grant_type == @jwt_bearer_grant do
    case AgentAuth.exchange_assertion(assertion, params["resource"]) do
      {:ok, response} -> agent_token_success(conn, response)
      {:error, reason} -> agent_token_error(conn, reason)
    end
  end

  def token(conn, _params), do: Boruta.Oauth.token(conn, __MODULE__)

  @impl true
  def token_success(conn, %TokenResponse{} = response) do
    data =
      %{
        token_type: response.token_type,
        access_token: response.access_token,
        expires_in: response.expires_in,
        refresh_token: response.refresh_token,
        id_token: response.id_token
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(data)
  end

  @impl true
  def token_error(conn, %Error{} = error),
    do:
      conn
      |> put_status(error.status)
      |> json(%{error: error.error, error_description: error.error_description})

  defp agent_token_success(conn, response) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(response)
  end

  defp agent_token_error(conn, reason) do
    {error, description} =
      case reason do
        :authorization_pending ->
          {"authorization_pending", "The user has not confirmed this request yet."}

        :slow_down ->
          {"slow_down", "Poll no faster than the interval returned at registration."}

        :expired_token ->
          {"expired_token", "The registration request has expired."}

        :invalid_grant ->
          {"invalid_grant", "The identity assertion is invalid or has expired."}

        _reason ->
          {"invalid_request", "The agent credential request is invalid."}
      end

    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:bad_request)
    |> json(%{error: error, error_description: description})
  end
end
