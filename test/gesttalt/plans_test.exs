defmodule Gesttalt.PlansTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Plans
  alias Gesttalt.Sites.Site

  test "every publishing feature is available during early access" do
    site = %Site{subscription_status: :inactive}

    assert Plans.early_access?()
    assert Plans.tier(site) == :free
    assert Plans.available?(site, :text_publishing)
    assert Plans.available?(site, :programmatic_publishing)
    assert Plans.available?(site, :custom_domains)
    assert Plans.available?(site, :media_uploads)
    assert Plans.available?(site, :custom_themes)
    assert Plans.authorize(site, :media_uploads) == :ok
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

  test "complimentary publications get the Publisher features without paying" do
    site = %Site{subscription_status: :comped}

    assert Plans.tier(site) == :publisher
    assert Plans.comped?(site)
    assert Plans.available?(site, :custom_domains)
    assert Plans.available?(site, :media_uploads)
    assert Plans.available?(site, :custom_themes)
  end

  test "ended subscriptions retain early access" do
    for status <- [:inactive, :canceled] do
      site = %Site{subscription_status: status}

      assert Plans.tier(site) == :free
      refute Plans.publisher?(site)
      assert Plans.available?(site, :custom_domains)
    end
  end
end
