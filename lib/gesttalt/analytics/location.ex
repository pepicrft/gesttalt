defmodule Gesttalt.Analytics.Location do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  @database_id :gesttalt_analytics_country

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

  def country(conn, opts \\ []) do
    conn
    |> get_req_header("cf-ipcountry")
    |> List.first()
    |> normalize_country()
    |> case do
      nil -> lookup_country(client_address(conn), opts)
      country -> country
    end
  end

  def load_database(database_url \\ database_url()) do
    settings = Application.get_env(:gesttalt, :analytics_country_database, [])

    cache_file =
      Keyword.get(
        settings,
        :cache_file,
        Path.join(System.tmp_dir!(), "gesttalt-analytics-country.mmdb.gz")
      )

    if Keyword.get(settings, :enabled, true) do
      case :locus.start_loader(@database_id, database_url, database_cache_file: cache_file) do
        :ok -> :ok
        {:error, :already_started} -> :ok
        {:error, _reason} -> :ok
      end
    end

    :ok
  end

  def reload_database(database_url) do
    case :locus.stop_loader(@database_id) do
      :ok -> load_database(database_url)
      {:error, :not_found} -> load_database(database_url)
    end
  end

  def describe(country, views) do
    case Map.fetch(@locations, country) do
      {:ok, location} -> Map.merge(location, %{country: country, views: views})
      :error -> %{country: country, label: country, views: views}
    end
  end

  defp normalize_country(country) when is_binary(country) do
    country = String.upcase(country)
    if country =~ ~r/^[A-Z]{2}$/, do: country
  end

  defp normalize_country(_country), do: nil

  defp client_address(conn) do
    conn
    |> get_req_header("x-gesttalt-client-ip")
    |> List.first()
    |> case do
      nil -> conn.remote_ip |> :inet.ntoa() |> to_string()
      addresses -> addresses |> String.split(",") |> List.first() |> String.trim()
    end
  end

  defp lookup_country(address, opts) do
    lookup = Keyword.get(opts, :lookup, &:locus.lookup(@database_id, &1))

    case lookup.(address) do
      {:ok, %{<<"country">> => %{<<"iso_code">> => country}}} -> normalize_country(country)
      _result -> nil
    end
  end

  def database_url(date \\ Date.utc_today()) do
    %{year: year, month: month} = date

    "https://download.db-ip.com/free/dbip-country-lite-#{year}-#{String.pad_leading(to_string(month), 2, "0")}.mmdb.gz"
  end
end
