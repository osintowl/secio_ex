defmodule SecioEx.Search do
  @moduledoc """
  Adds `stream/2` and `all/2` to a module that already has `search/2`.

  The page size has to be the endpoint's real page size. `Client.search/3`
  would otherwise send 50, and N-PORT rejects anything above 10.
  """

  @doc """
  Define `stream/2` and `all/2` for this module's `search/2`.

  `defaults` are applied with `Keyword.put_new/3` before the first request.
  Pass `size: 10` for N-PORT and `size: 100` for SRO filings.
  """
  defmacro pages(defaults \\ [size: 50]) do
    quote do
      @doc """
      Lazily walk this search, up to 10,000 records.

      Options match `search/2`. `:limit` stops after that many records.
      A failed page raises `SecioEx.PageError`.
      """
      def stream(query, opts \\ []) when is_binary(query) do
        SecioEx.Search.stream(
          fn page_opts -> search(query, page_opts) end,
          opts,
          unquote(defaults)
        )
      end

      @doc """
      Collect this search, up to 10,000 records.

      Returns `{:ok, records}`. A failure after the first page returns
      `{:error, %{reason: reason, from: from, records: records}}`.
      """
      def all(query, opts \\ []) when is_binary(query) do
        SecioEx.Search.all(fn page_opts -> search(query, page_opts) end, opts, unquote(defaults))
      end
    end
  end

  @doc false
  def stream(fetch, opts, defaults \\ [size: 50]) when is_function(fetch, 1) do
    opts = apply_defaults(opts, defaults)
    SecioEx.Pages.stream(fn page -> fetch.(Keyword.merge(opts, page)) end, opts)
  end

  @doc false
  def all(fetch, opts, defaults \\ [size: 50]) when is_function(fetch, 1) do
    opts = apply_defaults(opts, defaults)
    SecioEx.Pages.all(fn page -> fetch.(Keyword.merge(opts, page)) end, opts)
  end

  @doc false
  def apply_defaults(opts, defaults) do
    Enum.reduce(defaults, opts, fn {key, value}, acc -> Keyword.put_new(acc, key, value) end)
  end
end
