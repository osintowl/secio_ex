defmodule SecioEx.Form144 do
  require SecioEx.Search

  @moduledoc """
  Form 144 proposed sales.

  `POST https://api.sec-api.io/form-144`

  The page size is at most 50. `stream/2` and `all/2` walk offsets up to
  10,000. Past that, split the query with `SecioEx.Pages.date_windows/3`.
  """

  @doc """
  Search Form 144 filings.

  ## Examples

      SecioEx.Form144.search("issuerTicker:AAPL", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-144", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  SecioEx.Search.pages()
end
