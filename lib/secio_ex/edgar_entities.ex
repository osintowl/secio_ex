defmodule SecioEx.EdgarEntities do
  require SecioEx.Search

  @moduledoc """
  EDGAR entity index.

  `POST https://api.sec-api.io/edgar-entities`

  The default sort is `cikUpdatedAt` descending. This dataset does not accept
  a `filedAt` sort. The page size is at most 50.
  """

  @doc """
  Search EDGAR entities.

  ## Examples

      SecioEx.EdgarEntities.search("tickers:AAPL", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/edgar-entities", query, opts,
      size: 50,
      sort: SecioEx.Client.cik_updated_desc()
    )
  end

  SecioEx.Search.pages()
end
