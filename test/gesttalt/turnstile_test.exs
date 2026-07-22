defmodule Gesttalt.TurnstileTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Turnstile

  setup {Req.Test, :set_req_test_to_private}
  setup {Req.Test, :verify_on_exit!}

  test "accepts a token only for the configured hostname and action" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/turnstile/v0/siteverify"

      assert URI.decode_query(Req.Test.raw_body(conn)) == %{
               "remoteip" => "203.0.113.8",
               "response" => "valid-token",
               "secret" => "secret-key"
             }

      Req.Test.json(conn, %{
        "success" => true,
        "hostname" => "gesttalt.test",
        "action" => "account_registration"
      })
    end)

    assert :ok = Turnstile.verify("valid-token", options())
  end

  test "rejects a valid token issued for another context" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "success" => true,
        "hostname" => "other.test",
        "action" => "account_registration"
      })
    end)

    assert {:error, :unexpected_context} = Turnstile.verify("valid-token", options())
  end

  test "accepts a testing-key response only when explicitly enabled" do
    Req.Test.expect(__MODULE__, 2, fn conn ->
      Req.Test.json(conn, %{
        "success" => true,
        "hostname" => "example.com",
        "metadata" => %{"result_with_testing_key" => true}
      })
    end)

    assert {:error, :unexpected_context} = Turnstile.verify("test-token", options())
    assert :ok = Turnstile.verify("test-token", Keyword.put(options(), :allow_testing_key, true))
  end

  test "rejects missing and unsuccessful tokens" do
    assert {:error, :missing_token} = Turnstile.verify(nil, options())

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "success" => false,
        "error-codes" => ["invalid-input-response"]
      })
    end)

    assert {:error, {:rejected, ["invalid-input-response"]}} =
             Turnstile.verify("invalid-token", options())
  end

  defp options do
    [
      secret_key: "secret-key",
      expected_hostname: "gesttalt.test",
      expected_action: "account_registration",
      client_address: "203.0.113.8",
      request_options: [plug: {Req.Test, __MODULE__}]
    ]
  end
end
