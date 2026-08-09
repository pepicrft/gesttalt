defmodule Gesttalt.Themes.Variables do
  @moduledoc """
  The stable design-variable contract shared by every theme.

  The groups follow the Theme UI theme specification where it fits a publication,
  then expose those values as Cascading Style Sheets custom properties.
  """

  @reference_url "https://theme-ui.com/theme-spec"
  @max_value_bytes 500
  @unsafe_value ~r/[[:cntrl:];<>{}]|\/\*|\*\//u

  @groups [
    %{
      key: "colors",
      description: "Semantic colors used throughout the publication.",
      variables: [
        %{key: "text", description: "Body foreground color.", default: "#171411"},
        %{key: "background", description: "Body background color.", default: "#fdfbf7"},
        %{
          key: "primary",
          description: "Primary brand color for links and controls.",
          default: "#0062cc"
        },
        %{key: "secondary", description: "Secondary brand color.", default: "#5b4b8a"},
        %{key: "accent", description: "Contrasting emphasis color.", default: "#b45309"},
        %{
          key: "highlight",
          description: "Background color for highlighted content.",
          default: "#fff1a8"
        },
        %{key: "muted", description: "Faint background color.", default: "#f7f4ef"},
        %{key: "surface", description: "Raised or inset surface background.", default: "#f7f4ef"},
        %{key: "border", description: "Default border and divider color.", default: "#e4ddd2"},
        %{key: "mutedText", description: "Secondary text color.", default: "#5c5751"}
      ]
    },
    %{
      key: "fonts",
      description: "Font families for body, heading, and code content.",
      variables: [
        %{
          key: "body",
          description: "Default body font family.",
          default: ~s(system-ui, -apple-system, "Segoe UI", sans-serif)
        },
        %{
          key: "heading",
          description: "Default heading font family.",
          default: ~s(system-ui, -apple-system, "Segoe UI", sans-serif)
        },
        %{
          key: "monospace",
          description: "Default font family for code.",
          default: "ui-monospace, monospace"
        }
      ]
    },
    %{
      key: "fontSizes",
      description: "One shared type size for publication text, including headings.",
      variables: [
        %{key: "small", description: "Supporting and metadata text size.", default: "1rem"},
        %{key: "body", description: "Default body text size.", default: "1rem"},
        %{
          key: "lead",
          description: "Introductory and emphasized body text size.",
          default: "1rem"
        },
        %{
          key: "heading",
          description: "Primary page heading size.",
          default: "1rem"
        }
      ]
    },
    %{
      key: "fontWeights",
      description: "Semantic font weights.",
      variables: [
        %{key: "body", description: "Default body font weight.", default: "400"},
        %{key: "heading", description: "Default heading font weight.", default: "700"},
        %{key: "bold", description: "Default bold font weight.", default: "700"}
      ]
    },
    %{
      key: "lineHeights",
      description: "Semantic line heights.",
      variables: [
        %{key: "body", description: "Default body line height.", default: "1.7"},
        %{key: "heading", description: "Default heading line height.", default: "1.15"}
      ]
    },
    %{
      key: "space",
      description: "A compact spacing scale, ordered from smallest to largest.",
      variables: [
        %{key: "1", description: "Smallest spacing step.", default: "0.25rem"},
        %{key: "2", description: "Extra-small spacing step.", default: "0.5rem"},
        %{key: "3", description: "Small spacing step.", default: "1rem"},
        %{key: "4", description: "Medium spacing step.", default: "1.5rem"},
        %{key: "5", description: "Large spacing step.", default: "2.5rem"},
        %{key: "6", description: "Largest spacing step.", default: "4rem"}
      ]
    },
    %{
      key: "radii",
      description: "Border-radius values for controls and surfaces.",
      variables: [
        %{key: "small", description: "Small corner radius.", default: "0.2rem"},
        %{key: "medium", description: "Medium corner radius.", default: "0.5rem"},
        %{key: "large", description: "Large corner radius.", default: "1rem"},
        %{key: "round", description: "Fully rounded shape.", default: "9999px"}
      ]
    },
    %{
      key: "sizes",
      description: "Named layout sizes.",
      variables: [
        %{
          key: "content",
          description: "Maximum width of the primary reading column.",
          default: "760px"
        }
      ]
    },
    %{
      key: "shadows",
      description: "Named box shadows.",
      variables: [
        %{
          key: "card",
          description: "Default shadow for raised surfaces.",
          default: "0 1px 3px rgb(23 20 17 / 0.12)"
        }
      ]
    }
  ]

  def defaults do
    Map.new(@groups, fn group ->
      {group.key, Map.new(group.variables, &{&1.key, &1.default})}
    end)
  end

  def normalize(nil), do: defaults()

  def normalize(variables) when is_map(variables) do
    variables = stringify_keys(variables)

    case validate(variables) do
      :ok -> deep_merge(defaults(), variables)
      {:error, _reason} -> defaults()
    end
  end

  def normalize(_variables), do: defaults()

  def merge(current, updates) when is_map(updates) do
    updates = stringify_keys(updates)

    with :ok <- validate(updates) do
      {:ok, deep_merge(normalize(current), updates)}
    end
  end

  def merge(_current, _updates), do: {:error, "must be an object"}

  def validate(variables) when is_map(variables) do
    variables = stringify_keys(variables)
    group_specs = Map.new(@groups, &{&1.key, &1})

    Enum.reduce_while(variables, :ok, &validate_entry(&1, &2, group_specs))
  end

  def validate(_variables), do: {:error, "must be an object"}

  defp validate_entry({group_key, values}, :ok, group_specs) do
    case Map.fetch(group_specs, group_key) do
      :error ->
        {:halt, {:error, "contains unknown group #{inspect(group_key)}"}}

      {:ok, group} ->
        validate_group_entry(group, values)
    end
  end

  defp validate_group_entry(group, values) do
    case validate_group(group, values) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  def contract do
    %{
      reference: %{
        name: "Theme UI theme specification",
        url: @reference_url
      },
      update_shape:
        "Pass a partial variables object to update_theme_editing_session. Omitted values remain unchanged.",
      groups:
        Enum.map(@groups, fn group ->
          %{
            key: group.key,
            description: group.description,
            variables:
              Enum.map(group.variables, fn variable ->
                %{
                  key: variable.key,
                  custom_property: custom_property(group.key, variable.key),
                  description: variable.description,
                  default: variable.default
                }
              end)
          }
        end)
    }
  end

  def input_schema do
    %{
      type: "object",
      description:
        "Partial standard design variables. Prefer these for palette, typography, spacing, radius, size, and shadow changes.",
      properties:
        Map.new(@groups, fn group ->
          {group.key,
           %{
             type: "object",
             description: group.description,
             properties:
               Map.new(group.variables, fn variable ->
                 {variable.key, %{type: "string", description: variable.description}}
               end),
             additionalProperties: false
           }}
        end),
      additionalProperties: false
    }
  end

  def to_stylesheet(variables) do
    variables = normalize(variables)

    declarations =
      Enum.flat_map(@groups, fn group ->
        values = Map.fetch!(variables, group.key)

        Enum.map(group.variables, fn variable ->
          "  #{custom_property(group.key, variable.key)}: #{Map.fetch!(values, variable.key)};"
        end)
      end)

    Enum.join([":root {", Enum.join(declarations, "\n"), "}"], "\n")
  end

  defp validate_group(_group, values) when not is_map(values),
    do: {:error, "variable groups must be objects"}

  defp validate_group(group, values) do
    allowed = MapSet.new(group.variables, & &1.key)

    Enum.reduce_while(stringify_keys(values), :ok, fn {key, value}, :ok ->
      cond do
        not MapSet.member?(allowed, key) ->
          {:halt, {:error, "contains unknown variable #{group.key}.#{key}"}}

        not is_binary(value) or String.trim(value) == "" ->
          {:halt, {:error, "#{group.key}.#{key} must be a non-empty string"}}

        byte_size(value) > @max_value_bytes ->
          {:halt, {:error, "#{group.key}.#{key} is too long"}}

        Regex.match?(@unsafe_value, value) ->
          {:halt,
           {:error, "#{group.key}.#{key} must be one safe Cascading Style Sheets property value"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value),
        do: deep_merge(left_value, right_value),
        else: right_value
    end)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key
      value = if is_map(value), do: stringify_keys(value), else: value
      {key, value}
    end)
  end

  defp custom_property(group, variable) do
    "--gesttalt-#{kebab_case(group)}-#{kebab_case(variable)}"
  end

  defp kebab_case(value) do
    value
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
    |> String.downcase()
  end
end
