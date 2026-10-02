defmodule SecioEx.Watchlist do
  @moduledoc """
  Tickers and CIKs to highlight on the live monitor.

  A watchlist does not drop other filings. `--tickers` and `--ciks` do that.
  """

  def new(nil), do: %{tickers: MapSet.new(), ciks: MapSet.new()}

  def new(value) do
    {ciks, tickers} =
      value
      |> List.wrap()
      |> Enum.flat_map(&String.split(&1, ~r/\s*,\s*/, trim: true))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.split_with(&String.match?(&1, ~r/^\d+$/))

    filter = SecioEx.StreamFilter.new(tickers: tickers, ciks: ciks)
    %{tickers: MapSet.new(filter.tickers), ciks: MapSet.new(filter.ciks)}
  end

  def empty?(%{tickers: tickers, ciks: ciks}) do
    MapSet.size(tickers) == 0 and MapSet.size(ciks) == 0
  end

  def hit?(filing, watch) when is_map(filing) do
    not empty?(watch) and
      (Enum.any?(SecioEx.StreamFilter.tickers(filing), &MapSet.member?(watch.tickers, &1)) or
         Enum.any?(SecioEx.StreamFilter.ciks(filing), &MapSet.member?(watch.ciks, &1)))
  end

  def label(%{tickers: tickers, ciks: ciks}) do
    symbols =
      (tickers |> MapSet.to_list() |> Enum.sort()) ++
        (ciks |> MapSet.to_list() |> Enum.sort() |> Enum.map(&("CIK " <> &1)))

    Enum.join(symbols, " ")
  end
end
