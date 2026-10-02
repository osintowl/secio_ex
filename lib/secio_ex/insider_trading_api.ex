defmodule SecioEx.InsiderTradingApi do
  require SecioEx.Search

  @moduledoc """
  Insider trading from Forms 3, 4, and 5.

  `POST https://api.sec-api.io/insider-trading`

  The issuer ticker field is `issuer.tradingSymbol`.
  """

  @doc """
  Search insider transactions.

  ## Examples

      SecioEx.InsiderTradingApi.search("issuer.tradingSymbol:TSLA", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/insider-trading", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  @doc "Transactions in one issuer, by ticker."
  def by_ticker(ticker, opts \\ []) when is_binary(ticker) do
    search("issuer.tradingSymbol:#{String.upcase(String.trim(ticker))}", opts)
  end

  SecioEx.Search.pages()
end
