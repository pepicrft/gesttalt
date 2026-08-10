%{
  title: "Analytics country fallback",
  summary: "Analytics can now resolve country-level views without a proxy-provided country header."
}
---

Analytics now prefers the coarse country provided by Cloudflare when available. When it is not, Gesttalt resolves the country from the application-managed [DB-IP Lite](https://db-ip.com/db/lite.php) country database and the forwarded client address.

Gesttalt stores only the two-letter country code. It does not store the client address or send it to a location service.

Gesttalt downloads the current monthly database at startup and retries failed downloads. Set `GESTTALT_ANALYTICS_COUNTRY_DATABASE_PATH` to a writable `.mmdb.gz` file on durable storage to retain it between deployments. The Analytics page includes the attribution required by DB-IP Lite's [Creative Commons Attribution 4.0 International license](https://creativecommons.org/licenses/by/4.0/).
