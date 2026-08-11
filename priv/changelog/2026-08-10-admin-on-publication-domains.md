%{
  title: "Manage publications from their own domains",
  summary: "Open the dashboard at /admin on any verified publication domain."
}
---

The dashboard is now available at `/admin` on every active publication domain. When a browser needs to sign in, Gesttalt confirms the account on the central domain and returns it to the publication with a one-minute, single-use code bound to that browser and domain.

Dashboard requests verify that the signed-in account owns the requested publication. A strict script policy blocks inline and third-party theme scripts, and dashboard pages cannot be embedded in frames, so custom themes cannot cross the browser boundary into administrative actions. Liquid markup and custom styles continue to work as before.
