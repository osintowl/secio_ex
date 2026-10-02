defmodule SecioEx.SroFilings do
  require SecioEx.Search

  @moduledoc """
  Self-regulatory organization filings.

  `POST https://api.sec-api.io/sro`

  The default page size is 100 and the default sort is `issueDate` descending.
  """

  @sort [%{"issueDate" => %{"order" => "desc"}}]

  @doc """
  Search SRO filings.

  ## Examples

      SecioEx.SroFilings.search("sro:NASDAQ", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/sro", query, opts, size: 100, sort: @sort)
  end

  SecioEx.Search.pages(size: 100)
end
