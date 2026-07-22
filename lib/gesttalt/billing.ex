defmodule Gesttalt.Billing do
  @moduledoc "Creates hosted Stripe billing sessions and applies signed subscription events."

  alias Gesttalt.Sites
  alias Gesttalt.Sites.Site

  @stripe_url "https://api.stripe.com/v1"

  def monthly_price_euros do
    Application.get_env(:gesttalt, :stripe, [])[:monthly_price_euros] || 5
  end

  def configured?, do: match?({:ok, _config}, config())

  def checkout_url(%Site{} = site, customer_email, return_url) do
    with {:ok, config} <- config(),
         {:ok, response} <-
           Req.post(@stripe_url <> "/checkout/sessions",
             auth: {:bearer, config[:secret_key]},
             form:
               [
                 {"mode", "subscription"},
                 {"line_items[0][price]", config[:price_id]},
                 {"line_items[0][quantity]", "1"},
                 {"success_url", return_url <> "?checkout=success"},
                 {"cancel_url", return_url <> "?checkout=canceled"},
                 {"client_reference_id", to_string(site.id)},
                 {"metadata[site_id]", to_string(site.id)},
                 {"subscription_data[metadata][site_id]", to_string(site.id)}
               ] ++ customer_param(site, customer_email) ++ tax_params(config)
           ),
         %Req.Response{status: 200, body: %{"url" => url}} <- response do
      {:ok, url}
    else
      {:error, _reason} = error -> error
      %Req.Response{body: body} -> {:error, body}
      other -> {:error, other}
    end
  end

  def portal_url(%Site{stripe_customer_id: customer_id}, return_url)
      when is_binary(customer_id) do
    with {:ok, config} <- config(),
         {:ok, %Req.Response{status: 200, body: %{"url" => url}}} <-
           Req.post(@stripe_url <> "/billing_portal/sessions",
             auth: {:bearer, config[:secret_key]},
             form: [customer: customer_id, return_url: return_url]
           ) do
      {:ok, url}
    end
  end

  def portal_url(_site, _return_url), do: {:error, :customer_not_created}

  def process_webhook(raw_body, signature) do
    with {:ok, config} <- config(),
         :ok <- verify_signature(raw_body, signature, config[:webhook_secret]),
         {:ok, event} <- JSON.decode(raw_body) do
      apply_event(event)
    end
  end

  defp apply_event(%{"type" => "checkout.session.completed", "data" => %{"object" => object}}) do
    case site_from_object(object) do
      %Site{} = site ->
        Sites.update_billing(site, %{
          stripe_customer_id: object["customer"],
          stripe_subscription_id: object["subscription"],
          subscription_status: checkout_status(object["payment_status"])
        })

      _ ->
        :ok
    end
  end

  defp apply_event(%{
         "type" => "customer.subscription." <> _event,
         "data" => %{"object" => object}
       }) do
    case site_from_subscription(object) do
      %Site{} = site ->
        Sites.update_billing(site, %{
          stripe_customer_id: object["customer"],
          stripe_subscription_id: object["id"],
          subscription_status: subscription_status(object["status"]),
          cancel_at_period_end: object["cancel_at_period_end"] || false,
          subscription_ends_at: unix_datetime(object["current_period_end"])
        })

      _ ->
        :ok
    end
  end

  defp apply_event(_event), do: :ok

  defp site_from_object(%{"metadata" => %{"site_id" => site_id}}), do: Sites.get_site(site_id)

  defp site_from_object(%{"client_reference_id" => site_id}) when is_binary(site_id),
    do: Sites.get_site(site_id)

  defp site_from_object(_object), do: nil

  defp verify_signature(_body, _signature, nil), do: {:error, :billing_not_configured}

  defp verify_signature(body, signature, secret) when is_binary(signature) do
    values =
      signature
      |> String.split(",")
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.filter(&(length(&1) == 2))
      |> Map.new(fn [key, value] -> {key, value} end)

    with timestamp when is_binary(timestamp) <- values["t"],
         expected <-
           :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> body)
           |> Base.encode16(case: :lower),
         true <- secure_compare(expected, values["v1"] || ""),
         {unix, ""} <- Integer.parse(timestamp),
         true <- abs(System.system_time(:second) - unix) < 300 do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify_signature(_body, _signature, _secret), do: {:error, :invalid_signature}

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_compare(_left, _right), do: false

  defp subscription_status(status) when status in ~w(trialing active past_due canceled),
    do: String.to_existing_atom(status)

  defp subscription_status(_status), do: :inactive

  defp checkout_status(status) when status in ~w(paid no_payment_required), do: :active
  defp checkout_status(_status), do: :inactive

  defp site_from_subscription(object) do
    Sites.get_site_by_stripe_customer(object["customer"]) || site_from_object(object)
  end

  defp unix_datetime(value) when is_integer(value),
    do: value |> DateTime.from_unix!() |> DateTime.truncate(:second)

  defp unix_datetime(_value), do: nil

  defp customer_param(%Site{stripe_customer_id: id}, _email) when is_binary(id),
    do: [{"customer", id}]

  defp customer_param(_site, email) when is_binary(email), do: [{"customer_email", email}]
  defp customer_param(_site, _email), do: []

  defp tax_params(config) do
    if config[:automatic_tax] do
      [
        {"automatic_tax[enabled]", "true"},
        {"billing_address_collection", "required"},
        {"tax_id_collection[enabled]", "true"}
      ]
    else
      []
    end
  end

  defp config do
    config = Application.get_env(:gesttalt, :stripe, [])

    if config[:secret_key] && config[:price_id] && config[:webhook_secret],
      do: {:ok, config},
      else: {:error, :billing_not_configured}
  end
end
