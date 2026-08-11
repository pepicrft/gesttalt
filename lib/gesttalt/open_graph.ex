defmodule Gesttalt.OpenGraph do
  @moduledoc """
  Generates and serves theme-matched Open Graph images for publications.

  Images are rendered lazily by a headless browser pool (see
  [Carta](https://github.com/pepicrft/carta)) the first time they are requested,
  persisted durably through `Gesttalt.MediaStorage`, and proxied straight from
  storage on every later request. The storage key is derived by hashing the
  rendered HTML, so identical inputs share one object and a content or theme
  change produces a new object automatically.

  Every URL this module mints for a page carries a signature verified by
  `Gesttalt.OpenGraph.Signer`, so the image endpoint only renders requests that
  Gesttalt itself produced.
  """

  alias Gesttalt.Markdown
  alias Gesttalt.MediaStorage
  alias Gesttalt.OpenGraph.{Card, Signer}
  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.Post
  alias Gesttalt.Sites.Site

  @pool Gesttalt.OpenGraph.BrowserPool
  @render_opts [width: 1200, height: 630, quality: 90]
  @content_type "image/jpeg"

  @typedoc "A page whose Open Graph image can be rendered."
  @type subject :: {:post, Post.t()} | {:page, Post.t()} | {:note, Post.t()} | {:home, Site.t()}

  @typedoc "Context needed to mint an absolute, signed image URL."
  @type url_context :: %{site: Site.t(), theme: term(), base_url: String.t()}

  # --- URL building (invoked while rendering a page) ---

  @doc "Builds the absolute, signed Open Graph image URL for a subject."
  @spec image_url(subject(), url_context()) :: String.t()
  def image_url({:home, %Site{} = site}, %{base_url: base_url} = ctx),
    do: build_url(base_url, home_params(site, ctx))

  def image_url({kind, %Post{} = post}, %{base_url: base_url} = ctx)
      when kind in [:post, :page, :note],
      do: build_url(base_url, post_params(kind, post, ctx))

  defp build_url(base_url, params) do
    params = Map.put(params, "sig", Signer.sign(params, secret()))
    base_url <> "/og-image?" <> URI.encode_query(params)
  end

  defp post_params(kind, %Post{} = post, ctx) do
    %{
      "kind" => to_string(kind),
      "id" => post.id,
      "site" => ctx.site.id,
      "v" => version(post.updated_at, ctx.theme)
    }
  end

  defp home_params(%Site{} = site, ctx) do
    %{
      "kind" => "home",
      "site" => site.id,
      "v" => version(site.updated_at, ctx.theme)
    }
  end

  # The version binds the URL (and therefore its signature) to the current
  # content and full theme definition so crawlers refetch a fresh image after
  # an edit or theme change. It does not affect what gets rendered; the endpoint
  # always renders live data.
  defp version(subject_updated_at, theme) do
    "#{unix(subject_updated_at)}-#{theme_fingerprint(theme)}"
  end

  defp theme_fingerprint(theme) do
    theme
    |> Map.from_struct()
    |> Map.take([
      :built_in_theme,
      :variables,
      :stylesheet,
      :index_template,
      :article_template,
      :page_template,
      :photography_template
    ])
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp unix(%DateTime{} = datetime), do: Integer.to_string(DateTime.to_unix(datetime))
  defp unix(_other), do: "0"

  # --- Signature verification (invoked by the controller) ---

  @doc "Verifies the signature carried by an incoming image request."
  @spec verify_signature(map()) :: boolean()
  def verify_signature(params) when is_map(params),
    do: Signer.valid?(params, Map.get(params, "sig"), secret())

  # --- Rendering and caching (invoked by the controller) ---

  @doc "Resolves the subject named by `params`, builds its card, and returns the image."
  @spec render(Site.t(), map()) :: {:ok, binary()} | {:error, term()}
  def render(%Site{} = site, params) do
    with {:ok, subject} <- subject(site, params) do
      subject
      |> card_assigns(site)
      |> Map.put(:theme_fingerprint, theme_fingerprint(site.theme))
      |> Card.html()
      |> fetch_or_render()
    end
  end

  @doc """
  Returns the cached image if present, otherwise renders, stores, and returns it.

  The render is guarded by a cluster-wide lock keyed on the storage key so
  concurrent first hits render the image once rather than each spawning a browser.
  """
  @spec fetch_or_render(String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch_or_render(html) do
    key = storage_key(html)

    case MediaStorage.get(key) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} when reason in [:not_found, :enoent] -> render_locked(key, html)
      {:error, _reason} = error -> error
    end
  end

  @doc "The object storage key for a rendered card, derived from its HTML."
  @spec storage_key(String.t()) :: String.t()
  def storage_key(html), do: "og/" <> Carta.cache_key(html, @render_opts) <> ".jpg"

  defp render_locked(key, html) do
    with_lock(key, fn ->
      # Another request may have rendered while we waited for the lock.
      case MediaStorage.get(key) do
        {:ok, bytes} -> {:ok, bytes}
        {:error, reason} when reason in [:not_found, :enoent] -> render_and_store(key, html)
        {:error, _reason} = error -> error
      end
    end)
  end

  defp render_and_store(key, html) do
    with {:ok, jpeg} <- Carta.render(@pool, html, @render_opts),
         :ok <- MediaStorage.put(key, jpeg, @content_type) do
      {:ok, jpeg}
    end
  end

  defp with_lock(key, fun) do
    case :global.trans({{:gesttalt_og_render, key}, self()}, fun, [node() | Node.list()], 60) do
      :aborted -> fun.()
      result -> result
    end
  end

  # --- Subject resolution and card assigns ---

  defp subject(%Site{} = site, %{"kind" => "home"}), do: {:ok, {:home, site}}

  defp subject(%Site{} = site, %{"kind" => kind, "id" => id})
       when kind in ["post", "page", "note"] do
    kind_atom = String.to_existing_atom(kind)

    case Publishing.get_published_post(site, kind_atom, id) do
      %Post{} = post -> {:ok, {kind_atom, post}}
      nil -> {:error, :not_found}
    end
  end

  defp subject(_site, _params), do: {:error, :not_found}

  defp card_assigns({:home, %Site{} = site}, _site) do
    %{
      variables: theme_variables(site),
      variant: theme_variant(site),
      eyebrow: site.name,
      title: site.tagline || site.name,
      subtitle:
        if(site.tagline, do: "Writing, notes, and photographs from #{site.name}.", else: ""),
      meta: ""
    }
  end

  defp card_assigns({:note, %Post{} = post}, %Site{} = site) do
    %{
      variables: theme_variables(site),
      eyebrow: site.name,
      title: Markdown.to_text(post.body),
      subtitle: "",
      meta: post_meta(:note, post)
    }
  end

  defp card_assigns({kind, %Post{} = post}, %Site{} = site) do
    %{
      variables: theme_variables(site),
      variant: theme_variant(site),
      eyebrow: site.name,
      title: post.title,
      subtitle: post.excerpt || "",
      meta: post_meta(kind, post)
    }
  end

  defp post_meta(:post, %Post{} = post) do
    published_at = post.published_at || post.inserted_at

    date =
      if published_at, do: Calendar.strftime(published_at, "%B %-d, %Y"), else: ""

    date
  end

  defp post_meta(:page, %Post{} = post) do
    case post.published_at || post.inserted_at do
      nil -> ""
      published_at -> Calendar.strftime(published_at, "%B %-d, %Y")
    end
  end

  defp post_meta(:note, %Post{} = post), do: post_meta(:post, post)

  defp theme_variables(%Site{theme: %{variables: variables}}), do: variables
  defp theme_variables(_site), do: nil

  defp theme_variant(%Site{theme: %{built_in_theme: variant}})
       when variant in ["inquiry", "studio"],
       do: variant

  defp theme_variant(_site), do: "default"

  defp secret do
    :gesttalt
    |> Application.fetch_env!(GesttaltWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
