# Gesttalt

Gesttalt is a simple blogging platform for the agentic world. It is built with Phoenix, PostgreSQL, Liquid themes, and vanilla Cascading Style Sheets. Each account owns a site, publishes posts and pages, stores images, and may connect a custom domain. The browser editor, [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) application programming interface, and [Model Context Protocol](https://modelcontextprotocol.io/) server share the same tenant-scoped publishing model.

## Run locally

The project expects Elixir, Erlang, PostgreSQL, Node.js, and
[Mise](https://mise.jdx.dev/). From the repository root, install the pinned
tools once:

```sh
mise install
```

Mise assigns every clone or linked worktree a persistent numeric suffix through
Git metadata. The suffix scopes the Phoenix port and the development and test
PostgreSQL database names. Activate Mise in your shell, or
prefix commands with `mise exec --`. From this directory:

```sh
mise exec -- mix setup
mise exec -- mix phx.server
```

The server prints its assigned address when it starts. You can also inspect the
worktree-specific addresses with:

```sh
mise exec -- sh -c 'echo "$GESTTALT_URL"; echo "$GESTTALT_DEMO_URL"'
```

Both names end in `.localhost`, so they resolve to the loopback interface
without editing a hosts file. The development account is `demo@gesttalt.local`
with password `gesttalt-development`.

Run all local checks with:

```sh
mix format --check-formatted
mix format --check-formatted --dot-formatter .formatter.standard.exs
mix gettext.extract --merge
mix compile --warnings-as-errors
mix credo --strict
mix test
```

## Themes

A theme has five editable sources:

- `index_template` renders the publication home with Liquid.
- `article_template` renders a post with Liquid.
- `page_template` renders a page with Liquid.
- `variables` contains the standard color, typography, spacing, radius, size, and shadow values.
- `stylesheet` contains all theme styles.

The standard variables adapt the [Theme UI (user interface) theme specification](https://theme-ui.com/theme-spec) to Cascading Style Sheets custom properties. The built-in Paper theme in `priv/themes/paper` uses those properties and documents the available Liquid values through a complete working example. Liquid remains responsible for route-specific document structure, while variables are the preferred way for an agent to adjust the visual system. Theme editing happens through the [Model Context Protocol](https://modelcontextprotocol.io/) endpoint. `create_theme_editing_session` creates an in-process draft from the active theme and returns its preview address, current variables, and the variable contract. `update_theme_editing_session` accepts partial variable changes, preserves omitted values, and reloads connected previews. `publish_theme_editing_session` makes the draft active, while `discard_theme_editing_session` closes it without changing the publication.

## Import the existing blog

The importer reads the Zola `content/blog` and `content/pages` directories, preserves Markdown and front matter, and upserts entries by slug:

```sh
mix gesttalt.import_zola /path/to/pepicrft.me --email you@example.com
```

Run it once with the production release after the account has been bootstrapped. Re-running it updates matching content instead of creating duplicates.

## Programmatic publishing

Interactive documentation is available at `/api-docs`; the [OpenAPI](https://www.openapis.org/) document is served at `/api/openapi`. The Model Context Protocol endpoint is `/mcp`. Both use access tokens issued by the built-in [OAuth 2.0 authorization framework](https://oauth.net/2/) and enforce publication scopes.

Dynamic clients, including public mobile clients, register through `POST /oauth2/register`. Account owners can also create and revoke their own clients under `/admin/oauth-clients`.

Agents can discover a user-claimed registration flow at `/auth.md` and through the protected-resource metadata under `/.well-known`. An agent sends the user's email to `POST /agent/identity`, shows the returned six-digit code and verification address to the user, and polls the normal token endpoint. Gesttalt creates the account when necessary, the user signs in and confirms the code on Gesttalt, and the agent receives a one-hour publishing token plus a renewable service-signed identity assertion. The assertion never acts as a refresh token and no password is shared with the agent.

Production signs those identity assertions with a dedicated Rivest-Shamir-Adleman private key. Generate and store the Privacy-Enhanced Mail value as `GESTTALT_AGENT_AUTH_PRIVATE_KEY_PEM`; the chart reads it from `AGENT_AUTH_PRIVATE_KEY_PEM` in the external secret store. Development and test environments generate an ephemeral key at startup.

## Custom domains

Every publication receives a `{handle}.gesttalt.org` domain. A custom origin can be added under Settings. The owner proves control with the displayed Domain Name System text record and points the hostname to `domains.gesttalt.org` with a canonical name or address record. Verification activates the hostname only after both records resolve. Caddy asks the application whether a hostname is active before obtaining an on-demand Transport Layer Security certificate, so an unverified or misrouted hostname is never served.

Keep the routing record unproxied while completing verification. The request host selects the account and publication; content queries never accept a tenant identifier from the browser.

## Billing and media

The free plan allows unlimited posts and pages on a Gesttalt subdomain from the web, an application, or an agent. A five euro monthly Publisher plan unlocks custom domains, image and file uploads, and custom Liquid themes. The limit is feature-based rather than post-based, so writing and an existing archive never become a meter.

[Stripe](https://stripe.com/) hosts checkout and the customer portal. Signed webhook events update each site's subscription state. To enable billing, create one recurring monthly price in Stripe and set:

```sh
GESTTALT_STRIPE_SECRET_KEY=...
GESTTALT_STRIPE_PRICE_ID=price_...
GESTTALT_STRIPE_WEBHOOK_SECRET=whsec_...
GESTTALT_STRIPE_MONTHLY_PRICE_EUROS=5
GESTTALT_STRIPE_AUTOMATIC_TAX=false
```

Register `https://gesttalt.org/webhooks/stripe` as the webhook destination for completed checkout sessions and created, updated, or deleted subscriptions. Enable the Stripe customer portal so subscribers can manage their payment method and subscription. Automatic tax collection remains disabled until the business registration and tax treatment have been confirmed.

Uploaded images in the supported web formats are limited to ten megabytes. Development uses local storage, while production stores media under account-and-site-scoped keys in a private Hetzner Object Storage bucket and streams it through tenant-aware application routes.

## Localization

Interface copy uses Gettext domains so agent authorization, legal, billing, navigation, and marketing translations remain separate. Extract and merge the catalogs after changing translatable copy:

```sh
mix gettext.extract --merge
```

The continuous integration workflow verifies that extraction is clean and that every domain has an English catalog.

## Cluster deployment

`deploy/helm/gesttalt` packages Phoenix, Caddy, PostgreSQL through CloudNativePG, migration jobs, object-backed media, and External Secrets. The production values live in `deploy/values-production.yaml`.

The cluster entry point is `infra/k8s/workload-apps/gesttalt-production/gesttalt-helmrelease.yaml`. Flux reconciles that release into the `gesttalt` namespace through the production cluster configuration. Image automation watches `ghcr.io/pepicrft/gesttalt:main`, pins the latest digest in the production values, and commits that update back to the repository.

Before the first reconciliation, populate these required external secret-store
entries:

- `/gesttalt/SECRET_KEY_BASE` for Phoenix session and token signing;
- `/gesttalt/POSTGRES_PASSWORD` for the PostgreSQL application owner;
- `/gesttalt/AGENT_AUTH_PRIVATE_KEY_PEM` for Auth.md identity assertions;
- `/kubernetes/GHCR_PULL_USERNAME` and `/kubernetes/GHCR_PULL_TOKEN` for the
  GitHub Container Registry pull credentials.

Stripe and bootstrap account values are optional. Add their field mappings to
`deploy/values-production.yaml` only when the corresponding external values
have been configured.

Merging this project does not change Domain Name System records or create those secret values. Once they exist and the image has been published, Flux performs database creation, migrations, rollout, and subsequent image updates.
