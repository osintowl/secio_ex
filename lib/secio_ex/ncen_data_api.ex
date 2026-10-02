defmodule SecioEx.NcenDataApi do
  require SecioEx.Search

  @moduledoc """
  Form N-CEN annual reports.

  `POST https://api.sec-api.io/form-ncen`

  `:from` stops at 10,000. `:size` defaults to 50 and is at most 50. The
  default sort is `filedAt` descending.
  """

  @doc """
  Search Form N-CEN filings.

  ## Examples

      SecioEx.NcenDataApi.search("cik:0000842790", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-ncen", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  SecioEx.Search.pages()
end
