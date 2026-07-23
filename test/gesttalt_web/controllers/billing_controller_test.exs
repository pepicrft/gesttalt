defmodule GesttaltWeb.BillingControllerTest do
  use GesttaltWeb.ConnCase, async: true

  setup :register_and_log_in_user

  test "shows complete early access without pricing", %{conn: conn} do
    html = conn |> get(~p"/admin/billing") |> html_response(200)

    assert html =~ "Everything is included"
    assert html =~ "without paying or adding payment details"
    assert html =~ "Custom domains"
    assert html =~ "Image and file uploads"
    assert html =~ "Custom Liquid themes"
    refute html =~ "€"
    refute html =~ "per month"
    refute html =~ "Upgrade"
  end

  test "does not start checkout during early access", %{conn: conn} do
    conn = post(conn, ~p"/admin/billing/checkout")

    assert redirected_to(conn) == ~p"/admin/billing"

    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Every publishing feature is included during early access."
  end
end
