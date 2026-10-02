defmodule SecioEx.FormS1 do
  require SecioEx.Search

  @moduledoc """
  Registration statements and prospectus filings.

  `POST https://api.sec-api.io/form-s1-424b4`
  """

  @doc """
  Search S-1 and 424B4 filings.

  ## Examples

      SecioEx.FormS1.search("ticker:RBLX", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-s1-424b4", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  SecioEx.Search.pages()
end
