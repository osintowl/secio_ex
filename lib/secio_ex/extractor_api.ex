defmodule SecioEx.ExtractorApi do
  @base_url "https://api.sec-api.io/extractor"

  @valid_10k_items ~w(1 1A 1B 1C 2 3 4 5 6 7 7A 8 9 9A 9B 10 11 12 13 14 15)
  @valid_10q_items ~w(part1item1 part1item2 part1item3 part1item4 part2item1 part2item1a 
                      part2item2 part2item3 part2item4 part2item5 part2item6)
  @valid_8k_items ~w(1-1 1-2 1-3 1-4 1-5 2-1 2-2 2-3 2-4 2-5 2-6 3-1 3-2 3-3 4-1 4-2
                     5-1 5-2 5-3 5-4 5-5 5-6 5-7 5-8 6-1 6-2 6-3 6-4 6-5 6-6 6-10
                     7-1 8-1 9-1 signature)
  @moduledoc """
  A way to look for specific sec filing fields in 10-k, 10-q, and 8-k filings. 
  """

  @doc """
  Extracts a section from an SEC filing.

  ## Parameters
    - url: URL of the SEC filing
    - item: Section item to extract
    - opts: Additional options including :api_key and :type

  ## Examples
      # Extract Risk Factors (Item 1A) from a 10-K filing
      iex> SecioEx.ExtractorApi.extract(
        "https://www.sec.gov/.../tsla-10k_20201231.htm",
        "1A",
        api_key: "your_api_key"
      )
      {:ok, "Risk Factors content..."}

      # Extract with HTML formatting
      iex> SecioEx.ExtractorApi.extract(
        "https://www.sec.gov/.../aapl-20210327.htm",
        "8",
        api_key: "your_api_key",
        type: "html"
      )
      {:ok, "<html>Financial Statements content...</html>"}
  """
  def extract(url, item, opts \\ []) do
    with {:ok, filing_type} <- determine_filing_type(url),
         :ok <- validate_item(filing_type, item),
         :ok <- validate_return_type(opts[:type] || :text) do
      make_request(url, item, opts)
    end
  end

  @doc """
  Determines the filing type (10-K, 10-Q, or 8-K) from the URL.
  """
  def determine_filing_type(url) do
    downcased_url = String.downcase(url)

    cond do
      String.contains?(downcased_url, ["10-k", "10k"]) -> {:ok, :ten_k}
      String.contains?(downcased_url, ["10-q", "10q"]) -> {:ok, :ten_q}
      String.contains?(downcased_url, ["8-k", "8k"]) -> {:ok, :eight_k}
      true -> {:error, "Invalid filing type or URL"}
    end
  end

  @doc """
  Validates that the requested item is valid for the filing type.
  """
  def validate_item(filing_type, item) do
    case {filing_type, item} do
      {:ten_k, item} when item in @valid_10k_items -> :ok
      {:ten_q, item} when item in @valid_10q_items -> :ok
      {:eight_k, item} when item in @valid_8k_items -> :ok
      _ -> {:error, "Invalid item for filing type"}
    end
  end

  @doc """
  Validates the return type (text or html).
  """
  def validate_return_type(type) when type in [:text, :html], do: :ok
  def validate_return_type(_), do: {:error, "Invalid return type"}

  # Private Functions

  defp make_request(url, item, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    type = to_string(opts[:type] || :text)

    params = %{
      url: url,
      item: item,
      type: type
    }

    case use_auth_header?(opts) do
      true ->
        Req.get(@base_url,
          params: params,
          headers: [{"Authorization", api_key}]
        )
        |> handle_response()

      false ->
        Req.get(@base_url,
          params: Map.put(params, :token, api_key)
        )
        |> handle_response()
    end
  end

  defp use_auth_header?(opts) do
    Keyword.get(opts, :use_auth_header, true)
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, %{status_code: status, body: body}}
  end

  defp handle_response({:error, error}) do
    {:error, error}
  end
end
