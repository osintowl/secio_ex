defmodule SecioEx.AdministrativeProceedings do
  require SecioEx.Search

  @moduledoc """
  SEC administrative proceedings.

  `POST https://api.sec-api.io/sec-administrative-proceedings`

  The page size is at most 50. The default sort is `releasedAt` descending.
  A ticker query uses `entities.ticker`.
  """

  @doc """
  Search administrative proceedings.

  ## Examples

      SecioEx.AdministrativeProceedings.search("entities.ticker:IEP", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/sec-administrative-proceedings", query, opts,
      size: 50,
      sort: SecioEx.Client.released_at_desc()
    )
  end

  @doc "Proceedings that name a ticker."
  def by_ticker(ticker, opts \\ []) do
    ticker = ticker |> to_string() |> String.trim() |> String.upcase()

    if ticker == "" do
      raise ArgumentError, "ticker is empty"
    end

    search("entities.ticker:#{ticker}", opts)
  end

  SecioEx.Search.pages()
end
