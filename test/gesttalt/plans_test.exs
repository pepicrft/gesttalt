defmodule Gesttalt.PlansTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Plans
  alias Gesttalt.Sites.Site

  test "text publishing is available on the free plan" do
    site = %Site{subscription_status: :inactive}

    assert Plans.tier(site) == :free
    assert Plans.available?(site, :text_publishing)
    assert Plans.available?(site, :programmatic_publishing)
    assert Plans.authorize(site, :media_uploads) == {:error, :subscription_required}
  end

  test "Publisher features follow an active subscription" do
    for status <- [:trialing, :active, :past_due] do
      site = %Site{subscription_status: status}

      assert Plans.tier(site) == :publisher
      assert Plans.available?(site, :custom_domains)
      assert Plans.available?(site, :media_uploads)
      assert Plans.available?(site, :custom_themes)
    end
  end

  test "ended subscriptions return to the free plan" do
    for status <- [:inactive, :canceled] do
      site = %Site{subscription_status: status}

      assert Plans.tier(site) == :free
      refute Plans.publisher?(site)
    end
  end
end
