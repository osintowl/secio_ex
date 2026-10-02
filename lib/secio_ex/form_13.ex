defmodule SecioEx.Form13 do
  require SecioEx.Search

  @moduledoc """
  Institutional holdings and beneficial-ownership filings.

    * `holdings/2` — `POST /form-13f/holdings`
    * `cover_pages/2` — `POST /form-13f/cover-pages`
    * `beneficial_ownership/2` — `POST /form-13d-13g`
  """

  @doc """
  Search 13F holdings.

  ## Examples

      SecioEx.Form13.holdings("ticker:AAPL", api_key: "your_api_key")
  """
  def holdings(query, opts \\ []) when is_binary(query) do
    dataset("/form-13f/holdings", query, opts)
  end

  @doc "Search 13F cover pages."
  def cover_pages(query, opts \\ []) when is_binary(query) do
    dataset("/form-13f/cover-pages", query, opts)
  end

  @doc "Search Schedules 13D and 13G."
  def beneficial_ownership(query, opts \\ []) when is_binary(query) do
    dataset("/form-13d-13g", query, opts)
  end

  @doc "Walk 13F holdings."
  def stream_holdings(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> holdings(query, page) end, opts)
  end

  @doc "Collect 13F holdings."
  def all_holdings(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> holdings(query, page) end, opts)
  end

  @doc "Walk 13F cover pages."
  def stream_cover_pages(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> cover_pages(query, page) end, opts)
  end

  @doc "Collect 13F cover pages."
  def all_cover_pages(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> cover_pages(query, page) end, opts)
  end

  @doc "Walk Schedules 13D and 13G."
  def stream_beneficial_ownership(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> beneficial_ownership(query, page) end, opts)
  end

  @doc "Collect Schedules 13D and 13G."
  def all_beneficial_ownership(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> beneficial_ownership(query, page) end, opts)
  end

  defp dataset(path, query, opts) do
    SecioEx.Client.dataset(path, query, opts, size: 50, sort: SecioEx.Client.filed_at_desc())
  end
end
