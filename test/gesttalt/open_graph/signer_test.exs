defmodule Gesttalt.OpenGraph.SignerTest do
  use ExUnit.Case, async: true

  alias Gesttalt.OpenGraph.Signer

  @secret "test-secret-key-base-value-for-signing-og-urls"

  test "a freshly signed parameter map verifies" do
    params = %{"kind" => "post", "id" => "abc", "site" => "site-1", "v" => "1-2"}
    signature = Signer.sign(params, @secret)

    assert Signer.valid?(Map.put(params, "sig", signature), signature, @secret)
  end

  test "verification ignores an existing sig key in the params" do
    params = %{"kind" => "home", "site" => "site-1", "v" => "9-9"}
    signature = Signer.sign(params, @secret)

    # The incoming query map carries both the params and the signature.
    assert Signer.valid?(Map.put(params, "sig", signature), signature, @secret)
  end

  test "a tampered parameter fails verification" do
    params = %{"kind" => "post", "id" => "abc", "site" => "site-1", "v" => "1-2"}
    signature = Signer.sign(params, @secret)

    tampered = %{params | "id" => "def"}
    refute Signer.valid?(tampered, signature, @secret)
  end

  test "a signature from a different secret fails verification" do
    params = %{"kind" => "post", "id" => "abc"}
    signature = Signer.sign(params, "another-secret")

    refute Signer.valid?(params, signature, @secret)
  end

  test "missing or non-binary signatures are rejected" do
    params = %{"kind" => "home", "site" => "site-1"}

    refute Signer.valid?(params, nil, @secret)
    refute Signer.valid?(params, 123, @secret)
  end

  test "signatures are stable across calls" do
    params = %{"kind" => "post", "id" => "abc", "v" => "1-2"}

    assert Signer.sign(params, @secret) == Signer.sign(params, @secret)
  end
end
