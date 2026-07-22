defmodule Gesttalt.AccountRegistrationRateLimiter do
  @moduledoc """
  In-memory rate limiter for account registration attempts.

  Cloudflare provides the first layer at the network edge. This limiter keeps
  enforcing the application policy when traffic reaches the origin directly.
  """

  use Hammer, backend: :ets, algorithm: :sliding_window
end
