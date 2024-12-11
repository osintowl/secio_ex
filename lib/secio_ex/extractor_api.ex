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
      - opts: Additional options including:
        - :api_key (required): Your SEC API key
        - :type (optional): Return format, either :text or :html (default: :text)
        - :force_filing_type (optional): Force the filing type, must be one of "10-K", "10-Q", or "8-K"

    ## Examples
        # Extract Risk Factors (Item 1A) from a 10-K filing
        iex> SecioEx.ExtractorApi.extract(
          "https://www.sec.gov/.../tsla-10k_20201231.htm",
          "1A",
          api_key: "your_api_key"
        )
        {:ok, "Risk Factors content..."}

        # Extract with HTML formatting and forced filing type
        iex> SecioEx.ExtractorApi.extract(
          "https://www.sec.gov/.../example.htm",
          "1-1",
          api_key: "your_api_key",
          type: "html",
          force_filing_type: "8-K"
        )
        {:ok, "<html>Filing content...</html>"}
    """
    def extract(url, item, opts \\ []) do
      # Check for forced filing type first
      filing_type = case Keyword.get(opts, :force_filing_type) do
        "10-K" -> {:ok, :ten_k}
        "10-Q" -> {:ok, :ten_q}
        "8-K" -> {:ok, :eight_k}
        nil -> determine_filing_type(url)  # Only try to determine if not forced
        invalid -> {:error, "Invalid forced filing type: #{invalid}"}
      end

      with {:ok, type} <- filing_type,
          :ok <- validate_item(type, item),
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

    # Allow forcing filing type through opts
    filing_type = case Keyword.get(opts, :force_filing_type) do
      nil ->
        # Use the original determination if no force option
        case determine_filing_type(url) do
          {:ok, :ten_k} -> "10-K"
          {:ok, :ten_q} -> "10-Q"
          {:ok, :eight_k} -> "8-K"
          _ -> nil
        end
      forced_type when forced_type in ["10-K", "10-Q", "8-K"] ->
        forced_type
      invalid_type ->
        raise ArgumentError, "Invalid filing_type: #{invalid_type}. Must be one of: 10-K, 10-Q, 8-K"
    end

    params = %{
      url: url,
      item: item,
      type: type
    }

    # Only add filing_type to params if it's present
    params = if filing_type, do: Map.put(params, :filing_type, filing_type), else: params

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
