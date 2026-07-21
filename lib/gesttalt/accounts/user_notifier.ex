defmodule Gesttalt.Accounts.UserNotifier do
  @moduledoc false

  import Swoosh.Email

  alias Gesttalt.Accounts.User
  alias Gesttalt.Mailer

  @from {"gesttalt", "hello@pepicrft.me"}

  defp deliver(recipient, subject, content) do
    email =
      new()
      |> to(recipient)
      |> from(@from)
      |> subject(subject)
      |> text_body(render_text_body(recipient, content))
      |> html_body(render_html_body(recipient, content))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirm your new email", %{
      preheader: "Confirm the new email address for your gesttalt account.",
      heading: "Confirm your new email",
      message: "Use the button below to finish changing the email address on your account.",
      action_label: "Confirm new email",
      url: url,
      expiration: "This link expires in 7 days and can only be used once.",
      ignore: "If you did not request this change, you can safely ignore this email."
    })
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Your gesttalt login link", %{
      preheader: "Use this secure link to log in to gesttalt.",
      heading: "Log in to gesttalt",
      message: "Use the button below to securely log in to your account.",
      action_label: "Log in",
      url: url,
      expiration: "This link expires in 15 minutes and can only be used once.",
      ignore: "If you did not request this link, you can safely ignore this email."
    })
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your gesttalt account", %{
      preheader: "Confirm your email address and start publishing with gesttalt.",
      heading: "Confirm your account",
      message:
        "Thanks for joining gesttalt. Confirm your email address to finish setting up your account.",
      action_label: "Confirm account",
      url: url,
      expiration: "This link expires in 15 minutes and can only be used once.",
      ignore: "If you did not create this account, you can safely ignore this email."
    })
  end

  defp render_text_body(recipient, content) do
    """
    Hi #{recipient},

    #{content.message}

    #{content.action_label}: #{content.url}

    #{content.expiration}

    #{content.ignore}

    gesttalt. Independent publishing.
    """
  end

  defp render_html_body(recipient, content) do
    recipient = escape_html(recipient)
    preheader = escape_html(content.preheader)
    heading = escape_html(content.heading)
    message = escape_html(content.message)
    action_label = escape_html(content.action_label)
    url = escape_html(content.url)
    expiration = escape_html(content.expiration)
    ignore = escape_html(content.ignore)

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light">
        <title>#{heading}</title>
        <style>
          @media only screen and (max-width: 620px) {
            .email-shell { padding: 20px 12px !important; }
            .email-card { width: 100% !important; }
            .email-content { padding: 32px 24px !important; }
            .email-button { display: block !important; text-align: center !important; }
          }
        </style>
      </head>
      <body style="background:#f3f1eb; color:#181715; margin:0; padding:0;">
        <div style="display:none; font-size:1px; line-height:1px; max-height:0; max-width:0; opacity:0; overflow:hidden;">#{preheader}</div>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f3f1eb; border-collapse:collapse; width:100%;">
          <tr>
            <td class="email-shell" align="center" style="padding:40px 20px;">
              <table role="presentation" class="email-card" width="600" cellspacing="0" cellpadding="0" border="0" style="background:#fbfaf7; border:1px solid #dcd8cf; border-collapse:collapse; max-width:600px; width:600px;">
                <tr>
                  <td style="background:#0659c7; font-size:4px; height:4px; line-height:4px;">&nbsp;</td>
                </tr>
                <tr>
                  <td class="email-content" style="font-family:Arial, Helvetica, sans-serif; padding:44px 48px; text-align:left;">
                    <p style="color:#181715; font-size:18px; font-weight:700; line-height:24px; margin:0 0 36px;">gesttalt<span style="color:#0659c7;">.</span></p>
                    <h1 style="color:#181715; font-size:28px; font-weight:700; letter-spacing:-0.4px; line-height:36px; margin:0 0 20px;">#{heading}</h1>
                    <p style="color:#66615a; font-size:16px; line-height:25px; margin:0 0 12px;">Hi #{recipient},</p>
                    <p style="color:#181715; font-size:16px; line-height:25px; margin:0 0 28px;">#{message}</p>
                    <table role="presentation" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse; margin:0 0 28px;">
                      <tr>
                        <td style="background:#0659c7; border-radius:2px;">
                          <a class="email-button" href="#{url}" style="background:#0659c7; border:1px solid #0659c7; border-radius:2px; color:#ffffff; display:inline-block; font-family:Arial, Helvetica, sans-serif; font-size:16px; font-weight:700; line-height:20px; padding:13px 22px; text-decoration:none;">#{action_label}</a>
                        </td>
                      </tr>
                    </table>
                    <p style="color:#66615a; font-size:14px; line-height:22px; margin:0 0 8px;">If the button does not work, copy and paste this address into your browser:</p>
                    <p style="font-size:13px; line-height:20px; margin:0 0 28px; overflow-wrap:anywhere; word-break:break-all;"><a href="#{url}" style="color:#0659c7; text-decoration:underline;">#{url}</a></p>
                    <p style="background:#edf4fc; border:1px solid #b8cee9; color:#181715; font-size:14px; line-height:22px; margin:0 0 28px; padding:12px 14px;">#{expiration}</p>
                    <p style="color:#66615a; font-size:14px; line-height:22px; margin:0;">#{ignore}</p>
                  </td>
                </tr>
                <tr>
                  <td style="border-top:1px solid #dcd8cf; color:#66615a; font-family:Arial, Helvetica, sans-serif; font-size:13px; line-height:20px; padding:22px 48px;">gesttalt. Independent publishing.</td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  defp escape_html(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
