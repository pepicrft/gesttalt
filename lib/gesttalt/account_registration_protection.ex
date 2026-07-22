defmodule Gesttalt.AccountRegistrationProtection do
  @moduledoc """
  Applies local rate limits and Cloudflare Turnstile verification before an
  account is persisted or registration email is sent.
  """

  @type denial ::
          {:error, :rate_limited, non_neg_integer()}
          | {:error, :verification_failed}

  @spec check(String.t(), String.t() | nil, String.t() | nil, keyword()) :: :ok | denial()
  def check(email, client_address, turnstile_token, options) do
    if Keyword.fetch!(options, :enabled) do
      with :ok <- check_client_address_limit(client_address, options),
           :ok <- verify_turnstile(turnstile_token, client_address, options) do
        check_email_limit(email, options)
      end
    else
      :ok
    end
  end

  @spec site_key(keyword()) :: String.t() | nil
  def site_key(options) do
    if Keyword.fetch!(options, :enabled) do
      options |> Keyword.fetch!(:turnstile) |> Keyword.fetch!(:site_key)
    end
  end

  defp check_client_address_limit(client_address, options) do
    limiter = Keyword.fetch!(options, :rate_limiter)
    rate_limit = Keyword.fetch!(options, :rate_limit)

    hit(
      limiter,
      {:account_registration, :client_address, client_address || "unknown"},
      Keyword.fetch!(rate_limit, :period),
      Keyword.fetch!(rate_limit, :per_client_address)
    )
  end

  defp check_email_limit(email, options) do
    limiter = Keyword.fetch!(options, :rate_limiter)
    rate_limit = Keyword.fetch!(options, :rate_limit)

    hit(
      limiter,
      {:account_registration, :email, email_digest(email)},
      Keyword.fetch!(rate_limit, :period),
      Keyword.fetch!(rate_limit, :per_email)
    )
  end

  defp hit(limiter, key, period, limit) do
    case limiter.hit(key, period, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after} -> {:error, :rate_limited, retry_after}
    end
  end

  defp verify_turnstile(token, client_address, options) do
    verifier = Keyword.fetch!(options, :turnstile_verifier)
    turnstile = Keyword.fetch!(options, :turnstile)

    case verifier.verify(token,
           secret_key: Keyword.fetch!(turnstile, :secret_key),
           expected_hostname: Keyword.fetch!(turnstile, :hostname),
           expected_action: Keyword.fetch!(turnstile, :action),
           allow_testing_key: Keyword.get(turnstile, :allow_testing_key, false),
           client_address: client_address
         ) do
      :ok -> :ok
      {:error, _reason} -> {:error, :verification_failed}
    end
  end

  defp email_digest(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp email_digest(_email), do: :crypto.hash(:sha256, "")
end
