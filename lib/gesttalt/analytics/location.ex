defmodule Gesttalt.Analytics.Location do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  @locations %{
    "AU" => %{label: "Australia", latitude: -25, longitude: 133},
    "BR" => %{label: "Brazil", latitude: -10, longitude: -52},
    "CA" => %{label: "Canada", latitude: 56, longitude: -106},
    "DE" => %{label: "Germany", latitude: 51, longitude: 10},
    "ES" => %{label: "Spain", latitude: 40, longitude: -4},
    "FR" => %{label: "France", latitude: 46, longitude: 2},
    "GB" => %{label: "United Kingdom", latitude: 55, longitude: -3},
    "IN" => %{label: "India", latitude: 22, longitude: 79},
    "JP" => %{label: "Japan", latitude: 36, longitude: 138},
    "MX" => %{label: "Mexico", latitude: 24, longitude: -102},
    "US" => %{label: "United States", latitude: 40, longitude: -99}
  }

  def country(conn) do
    conn
    |> get_req_header("cf-ipcountry")
    |> List.first()
    |> normalize_country()
  end

  def describe(country, views) do
    case Map.fetch(@locations, country) do
      {:ok, location} -> Map.merge(location, %{country: country, views: views})
      :error -> %{country: country, label: country, views: views}
    end
  end

  defp normalize_country(country) when is_binary(country) do
    country = String.upcase(country)
    if Map.has_key?(@locations, country), do: country
  end

  defp normalize_country(_country), do: nil
end
