defmodule Gesttalt.Accounts.UserNotifierTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Accounts.User
  alias Gesttalt.Accounts.UserNotifier

  @url "https://gesttalt.org/users/log-in/example-token?from=email&source=test"

  test "sends a branded account confirmation with a plain-text fallback" do
    user = %User{email: "publisher@example.com"}

    assert {:ok, email} = UserNotifier.deliver_login_instructions(user, @url)

    assert email.from == {"gesttalt", "gesttalt@pepicrft.me"}
    assert email.subject == "Confirm your gesttalt account"
    assert email.text_body =~ "Confirm account: #{@url}"
    assert email.text_body =~ "expires in 15 minutes"
    assert email.html_body =~ "<h1"
    assert email.html_body =~ "Confirm your account"
    assert email.html_body =~ "Confirm account</a>"
    assert email.html_body =~ "from=email&amp;source=test"
    refute email.html_body =~ "from=email&source=test"
  end

  test "sends a login link to a confirmed user" do
    user = %User{email: "publisher@example.com", confirmed_at: DateTime.utc_now(:second)}

    assert {:ok, email} = UserNotifier.deliver_login_instructions(user, @url)

    assert email.subject == "Your gesttalt login link"
    assert email.text_body =~ "Log in: #{@url}"
    assert email.html_body =~ "Log in to gesttalt"
    assert email.html_body =~ ">Log in</a>"
  end

  test "sends an email change link with its longer expiry" do
    user = %User{email: "publisher@example.com"}

    assert {:ok, email} = UserNotifier.deliver_update_email_instructions(user, @url)

    assert email.subject == "Confirm your new email"
    assert email.text_body =~ "Confirm new email: #{@url}"
    assert email.text_body =~ "expires in 7 days"
    assert email.html_body =~ "Confirm your new email"
    assert email.html_body =~ ">Confirm new email</a>"
  end
end
