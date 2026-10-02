defmodule SecioEx.NportDataApi do
  require SecioEx.Search

  @moduledoc """
  Form N-PORT fund holdings.

  `POST https://api.sec-api.io/form-nport`

  The dataset returns at most 10 filings per response. `:size` defaults to 10.
  """

  @doc """
  Search N-PORT filings.

  ## Examples

      SecioEx.NportDataApi.search("genInfo.regCik:0000842790", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-nport", query, opts,
      size: 10,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  @doc """
  Filings for one registrant CIK.

  Pass the CIK in the form the dataset stores. The documented field is
  `genInfo.regCik`, often with leading zeros.
  """
  def by_registrant(cik, opts \\ []) do
    search("genInfo.regCik:#{cik}", opts)
  end

  SecioEx.Search.pages(size: 10)
end
