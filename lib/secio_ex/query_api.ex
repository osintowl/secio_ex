defmodule SecioEx.QueryApi do
  require SecioEx.Search

  @queryapi_url "https://api.sec-api.io"

  @moduledoc """
  The query api for working with SEC filings 
  """

  @doc """
  Performs a search query against the SEC Filings API.

  ## Parameters
    - query: String containing the Lucene query syntax
    - opts: Keyword list of options
      - from: Starting position for pagination (default: 0)
      - size: Number of results per page (default: 50, max: 50)
      - sort: List of sort criteria (default: [%{"filedAt" => %{"order" => "desc"}}])
      - api_key: Your SEC API key

  ## Examples
      iex> SecioEx.QueryApi.search("formType:\"10-Q\"", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 10000, "relation" => "gte"}, "filings" => [...]}}
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset(@queryapi_url, query, opts,
      from: 0,
      size: 50,
      sort: [%{"filedAt" => %{"order" => "desc"}}]
    )
  end

  @doc """
  Helper function to search for specific form types.

  ## Examples
      iex> SecioEx.QueryApi.search_form_type("10-K", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 10000, "relation" => "gte"}, "filings" => [...]}}
  """
  def search_form_type(form_type, opts \\ []) do
    query = ~s(formType:"#{form_type}")
    search(query, opts)
  end

  @doc """
  Helper function to search filings by ticker symbol.

  ## Examples
      iex> SecioEx.QueryApi.search_by_ticker("AAPL", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 5000, "relation" => "eq"}, "filings" => [...]}}
  """
  def search_by_ticker(ticker, opts \\ []) do
    query = "ticker:#{ticker}"
    search(query, opts)
  end

  @doc """
  Helper function to search filings within a date range.

  ## Examples
      iex> SecioEx.QueryApi.search_by_date_range("2024-01-01", "2024-01-31", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 3000, "relation" => "eq"}, "filings" => [...]}}
  """
  def search_by_date_range(start_date, end_date, opts \\ []) do
    query = "filedAt:[#{start_date} TO #{end_date}]"
    search(query, opts)
  end

  SecioEx.Search.pages()
end
