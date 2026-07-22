defmodule GesttaltWeb.AuthMarkdownController do
  use GesttaltWeb, :controller

  alias Gesttalt.AgentAuth

  def show(conn, _params) do
    document = """
    # Gesttalt agent authentication

    You are an agent. Gesttalt supports agentic registration through the auth.md protocol: discover, register, ask the user to claim the registration, exchange it for an access token, and manage the publication. Follow these steps in order.

    ## 1. Discover

    Fetch the protected resource metadata at #{url(~p"/.well-known/oauth-protected-resource/mcp")}, then fetch the first authorization server's metadata. The authorization server metadata is at #{url(~p"/.well-known/oauth-authorization-server")}.

    Use the protected resource `resource` value when exchanging credentials. Read the supported scopes before asking for consent.

    ## 2. Register with the user's email

    Gesttalt supports the `service_auth` identity type. Before sending the email, tell the user that Gesttalt publishing is the service and that the resulting credential can manage their complete publication. After they consent, send:

    ```http
    POST #{url(~p"/agent/identity")}
    Content-Type: application/json

    {"type":"service_auth","login_hint":"writer@example.com"}
    ```

    Keep the returned `claim_token` in memory until the ceremony finishes. Do not persist it. Show the returned `claim.user_code` and `claim.verification_uri` to the user in one message. Tell the user to enter the code on the Gesttalt page after signing in. Do not ask the user to send the code back to you.

    ## 3. Poll for the claim

    Poll #{url(~p"/oauth2/token")} no faster than `claim.interval` seconds:

    ```http
    POST #{url(~p"/oauth2/token")}
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.claim_grant()}&claim_token=<claim_token>
    ```

    `authorization_pending` means the user has not finished. On `slow_down`, add at least five seconds to the polling interval. If the user-code window expires while the registration remains active, request a fresh code with the same claim token and email:

    ```http
    POST #{url(~p"/agent/identity/claim")}
    Content-Type: application/json

    {"claim_token":"<claim_token>","email":"writer@example.com"}
    ```

    A successful poll returns a bearer access token and a service-signed `identity_assertion`. Use the access token immediately and retain the assertion until `assertion_expires`.

    ## 4. Connect and manage the publication

    Connect the access token to the Model Context Protocol server at #{url(~p"/mcp")} with `Authorization: Bearer <access_token>`. Start with `tools/list`; the server exposes content, media, theme, publication settings, custom domains, connected applications, and billing actions available in the dashboard.

    Never publish, delete, change a custom domain, create credentials, or begin a billing action unless the user explicitly asks.

    ## 5. Renew or revoke

    When the access token expires, exchange the service-signed assertion at #{url(~p"/oauth2/token")}:

    ```http
    POST #{url(~p"/oauth2/token")}
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.jwt_bearer_grant()}&assertion=<identity_assertion>&resource=#{url(~p"/mcp")}
    ```

    No refresh token is issued. If assertion exchange returns `invalid_grant`, restart registration. To revoke one access token, post `token=<access_token>&token_type_hint=access_token` to #{url(~p"/oauth2/revoke")}.

    ## Granted scopes

    - `content:read`: read posts and pages.
    - `content:write`: create, edit, publish, unpublish, and delete posts and pages.
    - `media:write`: manage images on a paid publishing plan.
    - `mcp`: use the complete agent management server.

    ## Service information

    - Documentation: #{url(~p"/docs")}
    - Pricing: #{url(~p"/admin/billing")}
    - Terms: #{url(~p"/terms")}
    - Privacy: #{url(~p"/privacy")}
    - Integration help: hola@pepicrft.me
    """

    conn
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, document)
  end
end
