defmodule SecioEx.EnforcementActions do
  require SecioEx.Search

  @moduledoc """
  SEC enforcement actions.

  `POST https://api.sec-api.io/sec-enforcement-actions`

  The page size is at most 50. The default sort is `releasedAt` descending.
  A ticker query uses `entities.ticker`. To pass 10,000 hits, call
  `SecioEx.Pages.all_between/3` with `date_field: "releasedAt"`.
  """

  @doc """
  Search enforcement actions.

  ## Examples

      SecioEx.EnforcementActions.search("entities.ticker:IEP", api_key: "your_api_key")
      SecioEx.EnforcementActions.search("tags:bribery", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/sec-enforcement-actions", query, opts,
      size: 50,
      sort: SecioEx.Client.released_at_desc()
    )
  end

  @doc "Actions that name a ticker, for example `IEP`."
  def by_ticker(ticker, opts \\ []) do
    search("entities.ticker:#{normalize_ticker(ticker)}", opts)
  end

  defp normalize_ticker(ticker) do
    ticker = ticker |> to_string() |> String.trim() |> String.upcase()

    if ticker == "" do
      raise ArgumentError, "ticker is empty"
    end

    ticker
  end

  SecioEx.Search.pages()
end
