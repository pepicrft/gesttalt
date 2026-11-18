%{
  title: "Fix repeated sign-in prompts in Model Context Protocol clients",
  summary: "Clients that do not request permissions during sign-in now receive access to the Gesttalt server."
}
---

Some [Model Context Protocol](https://modelcontextprotocol.io) clients do not say which permissions they need when they send you to Gesttalt to sign in. Those clients received an access token without permissions, so the server rejected it and the client asked you to sign in again. Gesttalt now grants these clients access to the Model Context Protocol server only, without access to the rest of the publishing interface. If a client kept asking you to sign in, disconnect it and connect it again.
