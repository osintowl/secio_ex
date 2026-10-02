defmodule SecioEx.DirectorsApi do
  require SecioEx.Search

  @directorsapi_url "https://api.sec-api.io/directors-and-board-members"

  @moduledoc """
  The Directors API for accessing information about directors and board members of public companies.
  """

  @doc """
  Performs a search query against the Directors & Board Members API.

  ## Parameters
    - query: String containing the Lucene query syntax
    - opts: Keyword list of options
      - from: Starting position for pagination (default: 0)
      - size: Number of results per page (default: 50, max: 50)
      - sort: List of sort criteria (default: [%{"filedAt" => %{"order" => "desc"}}])
      - api_key: Your SEC API key

  ## Examples
      iex> SecioEx.DirectorsApi.search("ticker:AMZN", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 25, "relation" => "eq"}, "data" => [...]}}
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset(@directorsapi_url, query, opts,
      from: 0,
      size: 50,
      sort: [%{"filedAt" => %{"order" => "desc"}}]
    )
  end

  @doc """
  Helper function to search directors by company ticker.

  ## Examples
      iex> SecioEx.DirectorsApi.search_by_ticker("AAPL", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 15, "relation" => "eq"}, "data" => [...]}}
  """
  def search_by_ticker(ticker, opts \\ []) do
    query = "ticker:#{ticker}"
    search(query, opts)
  end

  @doc """
  Helper function to search directors by name.

  ## Examples
      iex> SecioEx.DirectorsApi.search_by_name("Musk", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 5, "relation" => "eq"}, "data" => [...]}}
  """
  def search_by_name(name, opts \\ []) do
    query = "directors.name:#{name}"
    search(query, opts)
  end

  @doc """
  Helper function to search directors within a date range.

  ## Examples
      iex> SecioEx.DirectorsApi.search_by_date_range("2024-01-01", "2024-01-31", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 1000, "relation" => "eq"}, "data" => [...]}}
  """
  def search_by_date_range(start_date, end_date, opts \\ []) do
    query = "filedAt:[#{start_date} TO #{end_date}]"
    search(query, opts)
  end

  @doc """
  Helper function to search directors by CIK.

  ## Examples
      iex> SecioEx.DirectorsApi.search_by_cik("1018724", api_key: "your_api_key")
      {:ok, %{"total" => %{"value" => 10, "relation" => "eq"}, "data" => [...]}}
  """
  def search_by_cik(cik, opts \\ []) do
    query = "cik:#{cik}"
    search(query, opts)
  end

  SecioEx.Search.pages()
end
