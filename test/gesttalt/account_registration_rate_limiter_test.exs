defmodule Gesttalt.AccountRegistrationRateLimiterTest do
  use ExUnit.Case, async: true

  alias Gesttalt.AccountRegistrationRateLimiter

  test "denies hits beyond the configured limit" do
    key = {:test, System.unique_integer([:positive, :monotonic])}

    assert {:allow, 1} = AccountRegistrationRateLimiter.hit(key, :timer.minutes(1), 2)
    assert {:allow, 2} = AccountRegistrationRateLimiter.hit(key, :timer.minutes(1), 2)
    assert {:deny, retry_after} = AccountRegistrationRateLimiter.hit(key, :timer.minutes(1), 2)
    assert retry_after > 0
  end
end
