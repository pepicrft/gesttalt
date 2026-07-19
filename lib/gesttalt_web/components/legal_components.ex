defmodule GesttaltWeb.LegalComponents do
  @moduledoc "Components shared by the public legal and compliance pages."

  use GesttaltWeb, :html

  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :draft, :boolean, default: true
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
        <strong>{dgettext("legal", "Pre-launch draft.")}</strong>
        {dgettext(
          "legal",
          "The serviceable address, tax treatment, and remaining service-provider information will be completed before paid subscriptions are offered. This page is not yet a final legal notice."
        )}
      </aside>
      <div data-part="content">{render_slot(@inner_block)}</div>
    </article>
    """
  end
end
