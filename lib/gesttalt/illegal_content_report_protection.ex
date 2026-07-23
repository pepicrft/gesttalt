defmodule Gesttalt.IllegalContentReportProtection do
  @moduledoc "Applies abuse protection to the public illegal-content reporting form."

  def check(client_address, turnstile_token, options) do
    if Keyword.fetch!(options, :enabled) do
      with :ok <- check_rate_limit(client_address, options) do
        verify_turnstile(turnstile_token, client_address, options)
      end
    else
      :ok
    end
  end

  def site_key(options) do
    if Keyword.fetch!(options, :enabled) do
      options |> Keyword.fetch!(:turnstile) |> Keyword.fetch!(:site_key)
    end
  end

  defp check_rate_limit(client_address, options) do
    limiter = Keyword.fetch!(options, :rate_limiter)
    rate_limit = Keyword.fetch!(options, :rate_limit)

    case limiter.hit(
           {:illegal_content_report, :client_address, client_address || "unknown"},
           Keyword.fetch!(rate_limit, :period),
           Keyword.fetch!(rate_limit, :per_client_address)
         ) do
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
end
