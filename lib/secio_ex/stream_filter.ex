defmodule SecioEx.StreamFilter do
  @moduledoc """
  Client-side filter for the SEC filing stream.

  The stream itself is a firehose. An empty field means "no constraint".
  Constraints combine with AND. A form type also matches its `/A` amendment,
  so `8-K` matches `8-K` and `8-K/A` and does not match `8-K12B` or `424B4`.
  """

  defstruct form_types: [], tickers: [], ciks: []

  def new(opts \\ []) do
    opts = Map.new(opts)

    %__MODULE__{
      form_types: normalize_forms(Map.get(opts, :form_types, [])),
      tickers: normalize_tickers(Map.get(opts, :tickers, [])),
      ciks: normalize_ciks(Map.get(opts, :ciks, []))
    }
  end

  def active?(%__MODULE__{form_types: [], tickers: [], ciks: []}), do: false
  def active?(%__MODULE__{}), do: true

  def match?(%{} = filing, %__MODULE__{} = filter) do
    form_ok?(filing, filter) and ticker_ok?(filing, filter) and cik_ok?(filing, filter)
  end

  def match?(_, _), do: false

  def tickers(filing) do
    series =
      filing
      |> Map.get("seriesAndClassesContractsInformation", [])
      |> List.wrap()
      |> Enum.flat_map(fn
        %{} = series ->
          series
          |> Map.get("classesContracts", [])
          |> List.wrap()
          |> Enum.map(fn
            %{} = class -> class["ticker"]
            _ -> nil
          end)

        _ ->
          []
      end)

    [filing["ticker"] | series]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.upcase(String.trim(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def ciks(filing) do
    entity_ciks =
      filing
      |> Map.get("entities", [])
      |> List.wrap()
      |> Enum.map(fn
        %{} = entity -> entity["cik"]
        _ -> nil
      end)

    [filing["cik"] | entity_ciks]
    |> Enum.filter(&(is_binary(&1) or is_integer(&1)))
    |> Enum.map(&normalize_cik/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp form_ok?(_filing, %{form_types: []}), do: true

  defp form_ok?(filing, %{form_types: types}) do
    form = form_of(filing)
    Enum.any?(types, fn wanted -> form == wanted or form == wanted <> "/A" end)
  end

  defp ticker_ok?(_filing, %{tickers: []}), do: true

  defp ticker_ok?(filing, %{tickers: wanted}) do
    Enum.any?(tickers(filing), &(&1 in wanted))
  end

  defp cik_ok?(_filing, %{ciks: []}), do: true

  defp cik_ok?(filing, %{ciks: wanted}) do
    Enum.any?(ciks(filing), &(&1 in wanted))
  end

  defp form_of(filing) do
    filing
    |> Map.get("formType", "")
    |> to_string()
    |> String.trim()
    |> String.upcase()
  end

  defp normalize_forms(value) do
    value
    |> split()
    |> Enum.map(&String.upcase/1)
    |> Enum.uniq()
  end

  defp normalize_tickers(value) do
    value
    |> split()
    |> Enum.map(&String.upcase/1)
    |> Enum.uniq()
  end

  defp normalize_ciks(value) do
    value
    |> split()
    |> Enum.map(&normalize_cik/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_cik(cik) do
    cik
    |> to_string()
    |> String.trim()
    |> String.trim_leading("0")
    |> case do
      "" -> "0"
      trimmed -> trimmed
    end
  end

  defp split(list) when is_list(list), do: Enum.flat_map(list, &split/1)

  defp split(bin) when is_binary(bin) do
    bin
    |> String.split(~r/\s*,\s*/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split(nil), do: []
  defp split(other), do: [to_string(other)]
end
