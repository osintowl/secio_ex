defmodule SecioEx.SubsidiaryApi do
  require SecioEx.Search

  @moduledoc """
  Exhibit 21 subsidiaries.

  `POST https://api.sec-api.io/subsidiaries`

  `ticker:MSFT` returns Microsoft's disclosed subsidiaries. `cik` is the
  parent company CIK without extra leading zeros.
  """

  @doc """
  Search subsidiary lists.

  ## Examples

      SecioEx.SubsidiaryApi.search("ticker:MSFT", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/subsidiaries", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  @doc "Subsidiary lists for a parent ticker."
  def by_ticker(ticker, opts \\ []) when is_binary(ticker) do
    search("ticker:#{String.upcase(String.trim(ticker))}", opts)
  end

  @doc "Subsidiary lists for a parent CIK."
  def by_cik(cik, opts \\ []) do
    search("cik:#{cik}", opts)
  end

  SecioEx.Search.pages()
end
