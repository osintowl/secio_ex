defmodule SecioEx.OutstandingSharesApi do
  @moduledoc """
  Outstanding shares and public float.

  `GET https://api.sec-api.io/float`

  Pass `:ticker` or `:cik`. The request is not sent when neither is set.
  """

  @doc """
  Fetch the float for a ticker or a CIK.

  ## Examples

      SecioEx.OutstandingSharesApi.get(ticker: "AAPL", api_key: "your_api_key")
      SecioEx.OutstandingSharesApi.by_cik("320193", api_key: "your_api_key")
  """
  def get(opts \\ []) do
    params =
      cond do
        present?(opts[:ticker]) and present?(opts[:cik]) ->
          raise ArgumentError, "pass :ticker or :cik, not both"

        present?(opts[:ticker]) ->
          [ticker: opts[:ticker] |> to_string() |> String.trim()]

        present?(opts[:cik]) ->
          [cik: opts[:cik] |> to_string() |> String.trim()]

        true ->
          raise ArgumentError, "pass :ticker or :cik"
      end

    SecioEx.Client.get("/float", Keyword.put(opts, :params, params))
  end

  @doc "Float for a ticker."
  def by_ticker(ticker, opts \\ []) do
    get(Keyword.put(opts, :ticker, ticker))
  end

  @doc "Float for a CIK."
  def by_cik(cik, opts \\ []) do
    get(Keyword.put(opts, :cik, cik))
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_integer(value), do: true
  defp present?(_), do: false
end
