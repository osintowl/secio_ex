defmodule SecioEx.AuditFees do
  require SecioEx.Search

  @moduledoc """
  Audit fees disclosed in annual filings.

  `POST https://api.sec-api.io/audit-fees`

  The page size is 50. Results are sorted by `filedAt` descending.
  """

  @doc """
  Search audit fee records.

  ## Examples

      SecioEx.AuditFees.search("ticker:AAPL", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/audit-fees", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  SecioEx.Search.pages()
end
