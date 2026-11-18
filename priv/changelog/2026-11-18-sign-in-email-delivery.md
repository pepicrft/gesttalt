%{
  title: "Fix missing sign-in emails",
  summary: "Sign-in and confirmation emails are delivered again."
}
---

Gesttalt stopped sending email after the mail relay it used moved to a new address, so sign-in links, account confirmations, and email change confirmations never arrived. Gesttalt now sends mail through the relay's current address. If you requested a sign-in link and it never arrived, request a new one.
