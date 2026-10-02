defmodule SecioEx.RegA do
  require SecioEx.Search

  @moduledoc """
  Regulation A offering filings.

  Each endpoint is its own Lucene search, with a page size of 50:

    * `search/2` — `POST /reg-a/search`
    * `form_1a/2` — `POST /reg-a/form-1a`
    * `form_1k/2` — `POST /reg-a/form-1k`
    * `form_1z/2` — `POST /reg-a/form-1z`

  Each has a `stream` and `all` pair. `stream/2` walks the search endpoint.
  """

  @doc "Search the Regulation A index."
  def search(query, opts \\ []) when is_binary(query), do: dataset("/reg-a/search", query, opts)

  @doc "Search Form 1-A filings."
  def form_1a(query, opts \\ []) when is_binary(query), do: dataset("/reg-a/form-1a", query, opts)

  @doc "Search Form 1-K filings."
  def form_1k(query, opts \\ []) when is_binary(query), do: dataset("/reg-a/form-1k", query, opts)

  @doc "Search Form 1-Z filings."
  def form_1z(query, opts \\ []) when is_binary(query), do: dataset("/reg-a/form-1z", query, opts)

  @doc "Walk Form 1-A results."
  def stream_form_1a(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> form_1a(query, page) end, opts)
  end

  @doc "Collect Form 1-A results."
  def all_form_1a(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> form_1a(query, page) end, opts)
  end

  @doc "Walk Form 1-K results."
  def stream_form_1k(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> form_1k(query, page) end, opts)
  end

  @doc "Collect Form 1-K results."
  def all_form_1k(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> form_1k(query, page) end, opts)
  end

  @doc "Walk Form 1-Z results."
  def stream_form_1z(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.stream(fn page -> form_1z(query, page) end, opts)
  end

  @doc "Collect Form 1-Z results."
  def all_form_1z(query, opts \\ []) when is_binary(query) do
    SecioEx.Search.all(fn page -> form_1z(query, page) end, opts)
  end

  defp dataset(path, query, opts) do
    SecioEx.Client.dataset(path, query, opts, size: 50, sort: SecioEx.Client.filed_at_desc())
  end

  SecioEx.Search.pages()
end
