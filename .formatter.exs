[
  import_deps: [:ecto, :ecto_sql, :open_api_spex, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Quokka, Phoenix.LiveView.HTMLFormatter],
  quokka: [only: [:line_length]],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
