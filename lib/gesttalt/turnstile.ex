defmodule Gesttalt.Turnstile do
  @moduledoc "Server-side verification for Cloudflare Turnstile tokens."

  @siteverify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @spec verify(String.t() | nil, keyword()) :: :ok | {:error, term()}
  def verify(token, options) when is_binary(token) and token != "" do
    request_options = Keyword.get(options, :request_options, [])

    form =
      [
        secret: Keyword.fetch!(options, :secret_key),
        response: token
      ]
      |> maybe_add_client_address(options[:client_address])

    defaults = [
      form: form,
      retry: false,
      receive_timeout: 5_000,
      connect_options: [timeout: 3_000]
    ]

    case Req.post(@siteverify_url, Keyword.merge(defaults, request_options)) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"success" => true} = body
       }} ->
        validate_context(body, options)

      {:ok, %Req.Response{body: body}} when is_map(body) ->
        {:error, {:rejected, Map.get(body, "error-codes", [])}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_response, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  def verify(_token, _options), do: {:error, :missing_token}

  defp maybe_add_client_address(form, nil), do: form

  defp maybe_add_client_address(form, client_address),
    do: Keyword.put(form, :remoteip, client_address)

  defp validate_context(body, options) do
    cond do
      options[:allow_testing_key] == true and
          get_in(body, ["metadata", "result_with_testing_key"]) == true ->
        :ok

      body["hostname"] == Keyword.fetch!(options, :expected_hostname) and
          body["action"] == Keyword.fetch!(options, :expected_action) ->
        :ok

      true ->
        {:error, :unexpected_context}
    end
  end
end
