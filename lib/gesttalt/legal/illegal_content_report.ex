defmodule Gesttalt.Legal.IllegalContentReport do
  @moduledoc "A notice submitted through Gesttalt's illegal-content reporting route."

  use Ecto.Schema

  import Ecto.Changeset

  @statuses [:received, :reviewing, :resolved]

  schema "illegal_content_reports" do
    field :reference, :string
    field :content_url, :string
    field :explanation, :string
    field :reporter_name, :string
    field :reporter_email, :string
    field :anonymous_sensitive_offence, :boolean, default: false
    field :good_faith, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :received
    field :decision, :string
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :content_url,
      :explanation,
      :reporter_name,
      :reporter_email,
      :anonymous_sensitive_offence,
      :good_faith
    ])
    |> update_change(:content_url, &String.trim/1)
    |> update_change(:explanation, &String.trim/1)
    |> update_change(:reporter_name, &String.trim/1)
    |> update_change(:reporter_email, &String.trim/1)
    |> validate_required([:content_url, :explanation])
    |> validate_length(:content_url, max: 2_048)
    |> validate_length(:explanation, min: 20, max: 20_000)
    |> validate_length(:reporter_name, max: 200)
    |> validate_length(:reporter_email, max: 320)
    |> validate_format(:reporter_email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_content_url()
    |> validate_reporter()
    |> validate_acceptance(:good_faith,
      message: "must be confirmed before the report can be submitted"
    )
    |> put_change(:reference, reference())
    |> unique_constraint(:reference)
  end

  def resolve_changeset(report, decision, resolved_at) do
    report
    |> cast(%{decision: decision, resolved_at: resolved_at, status: :resolved}, [
      :decision,
      :resolved_at,
      :status
    ])
    |> validate_required([:decision, :resolved_at, :status])
    |> validate_length(:decision, min: 20, max: 20_000)
  end

  defp validate_content_url(changeset) do
    validate_change(changeset, :content_url, fn :content_url, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _uri ->
          [content_url: "must be a complete http or https address"]
      end
    end)
  end

  defp validate_reporter(changeset) do
    if get_field(changeset, :anonymous_sensitive_offence) do
      changeset
    else
      validate_required(changeset, [:reporter_name, :reporter_email],
        message:
          "is required unless the report concerns suspected child sexual abuse or exploitation"
      )
    end
  end

  defp reference do
    "G-" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end
end
