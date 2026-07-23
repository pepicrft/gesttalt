defmodule GesttaltWeb.LegalComponents do
  @moduledoc "Components shared by the public legal and compliance pages."

  use GesttaltWeb, :html

  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :draft, :boolean, default: false
  slot :inner_block, required: true

  def legal_document(assigns) do
    ~H"""
    <article id="legal-document">
      <header data-part="header">
        <p data-part="eyebrow">{@eyebrow}</p>
        <h1 data-part="title">{@title}</h1>
        <p data-part="description">{@description}</p>
      </header>
      <aside :if={@draft} data-part="draft-notice" role="status">
        <strong>{dgettext("legal", "Draft pending a publishable address.")}</strong>
        {dgettext(
          "legal",
          "A serviceable business address is legally required before this page can become final. The private residential address has not been published."
        )}
      </aside>
      <div data-part="content">{render_slot(@inner_block)}</div>
    </article>
    """
  end
end
