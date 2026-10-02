defmodule SecioEx.FormC do
  require SecioEx.Search

  @moduledoc """
  Form C crowdfunding offerings.

  `POST https://api.sec-api.io/form-c`

  Results are sorted by `filedAt` descending. The page size is at most 50.
  """

  @doc """
  Search Form C filings.

  ## Examples

      SecioEx.FormC.search("issuer.cik:0001234567", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-c", query, opts, size: 50, sort: SecioEx.Client.filed_at_desc())
  end

  SecioEx.Search.pages()
end
