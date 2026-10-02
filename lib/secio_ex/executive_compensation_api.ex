defmodule SecioEx.ExecutiveCompensationApi do
  require SecioEx.Search

  @moduledoc """
  Executive compensation.

  A ticker uses `GET /compensation/:TICKER`. A Lucene query uses
  `POST /compensation`.
  """

  @doc """
  Compensation for one ticker. The ticker is sent in upper case.

  ## Examples

      SecioEx.ExecutiveCompensationApi.by_ticker("aapl", api_key: "your_api_key")
  """
  def by_ticker(ticker, opts \\ []) when is_binary(ticker) do
    ticker = ticker |> String.trim() |> String.upcase()

    if ticker == "" do
      raise ArgumentError, "ticker is empty"
    end

    SecioEx.Client.get("/compensation/" <> SecioEx.Client.encode_segment(ticker), opts)
  end

  @doc """
  Search compensation records.

  ## Examples

      SecioEx.ExecutiveCompensationApi.search("ticker:AAPL", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/compensation", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  SecioEx.Search.pages()
end
