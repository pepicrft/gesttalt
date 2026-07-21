defmodule Gesttalt.Plans do
  @moduledoc "Defines the free and paid publishing capabilities in one place."

  alias Gesttalt.Sites.Site

  # :comped grants every Publisher feature without a Stripe subscription. It is set from an
  # operator console, never from a webhook, so Stripe events can not take it away.
  @paid_statuses [:trialing, :active, :past_due, :comped]
  @publisher_features [:custom_domains, :media_uploads, :custom_themes]

  def tier(%Site{} = site), do: if(publisher?(site), do: :publisher, else: :free)

  def publisher?(%Site{subscription_status: status}), do: status in @paid_statuses

  def comped?(%Site{subscription_status: status}), do: status == :comped

  def available?(%Site{} = site, feature) when feature in @publisher_features,
    do: publisher?(site)

  def available?(%Site{}, feature) when feature in [:text_publishing, :programmatic_publishing],
    do: true

  def authorize(%Site{} = site, feature) do
    if available?(site, feature), do: :ok, else: {:error, :subscription_required}
  end
end
