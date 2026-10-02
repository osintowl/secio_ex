defmodule SecioEx.XbrlToJson do
  @moduledoc """
  Convert a filing's XBRL into JSON.

  `GET https://api.sec-api.io/xbrl-to-json`

  Provide exactly one of `:htm_url`, `:xbrl_url`, or `:accession_no`.
  The request is not sent when that is missing. Read the JSON with
  `SecioEx.XbrlParser`.

  XBRL conversion is slow, so this call waits up to 120 seconds unless
  `:receive_timeout` is set.
  """

  @sources [
    htm_url: "htm-url",
    xbrl_url: "xbrl-url",
    accession_no: "accession-no"
  ]

  @doc """
  Convert one filing.

  ## Examples

      SecioEx.XbrlToJson.convert(
        accession_no: "0000320193-20-000096",
        api_key: "your_api_key"
      )
  """
  def convert(opts \\ []) when is_list(opts) do
    {param, value} = source!(opts)

    opts =
      opts
      |> Keyword.put(:params, [{param, value}])
      |> Keyword.put_new(:receive_timeout, 120_000)

    SecioEx.Client.get("/xbrl-to-json", opts)
  end

  defp source!(opts) do
    given =
      Enum.filter(@sources, fn {key, _param} -> present?(opts[key]) end)

    case given do
      [{key, param}] ->
        {param, opts[key] |> to_string() |> String.trim()}

      [] ->
        raise ArgumentError, "provide one of :htm_url, :xbrl_url, or :accession_no"

      _ ->
        raise ArgumentError, "provide only one of :htm_url, :xbrl_url, or :accession_no"
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
