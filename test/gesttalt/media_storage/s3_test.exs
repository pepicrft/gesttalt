defmodule Gesttalt.MediaStorage.S3Test do
  use ExUnit.Case, async: true

  alias Gesttalt.MediaStorage.S3

  setup {Req.Test, :set_req_test_to_private}
  setup {Req.Test, :verify_on_exit!}

  test "writes an account-scoped object with a signed request" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/gesttalt-media/accounts/7/sites/12/image.png"
      assert Req.Test.raw_body(conn) == "image bytes"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["image/png"]
      assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")
      assert String.starts_with?(authorization, "AWS4-HMAC-SHA256 Credential=access-key/")
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert :ok =
             S3.put(
               "accounts/7/sites/12/image.png",
               "image bytes",
               "image/png",
               options()
             )
  end

  test "reads an object" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/gesttalt-media/accounts/7/sites/12/image.png"
      Plug.Conn.send_resp(conn, 200, "stored image")
    end)

    assert {:ok, "stored image"} =
             S3.get("accounts/7/sites/12/image.png", options())
  end

  test "deletes an object idempotently" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert :ok = S3.delete("accounts/7/sites/12/image.png", options())
  end

  defp options do
    [
      endpoint: "https://fsn1.example.test",
      region: "fsn1",
      bucket: "gesttalt-media",
      access_key_id: "access-key",
      secret_access_key: "secret-key",
      request_options: [plug: {Req.Test, __MODULE__}]
    ]
  end
end
