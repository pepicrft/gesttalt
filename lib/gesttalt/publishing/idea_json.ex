defmodule Gesttalt.Publishing.IdeaJSON do
  @moduledoc "Stable JSON representation of a Gesttalt conversation idea."

  alias Gesttalt.Publishing.Idea

  @doc "Serializes one idea for the publishing interface and Model Context Protocol tools."
  def render(%Idea{} = idea) do
    %{
      id: idea.id,
      title: idea.title,
      notes: idea.notes,
      inserted_at: idea.inserted_at,
      updated_at: idea.updated_at
    }
  end
end
