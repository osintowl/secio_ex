# lib/secio_ex/mapping_api.ex
defmodule SecioEx.MappingApi do
  @base_url "https://api.sec-api.io/mapping"

  @moduledoc """
  A mapping of various ids, tickers, etc. 
  """

  @type mapping_opts :: [
          api_key: String.t()
        ]

  @doc """
  Maps a CIK to company details.

  ## Parameters
    - cik: The CIK number (without leading zeros)
    - opts: Keyword list of options including :api_key

  ## Examples
      iex> SecioEx.MappingApi.map_cik("1318605", api_key: "your_api_key")
      {:ok, [%{
        "name" => "Tesla Inc",
        "ticker" => "TSLA",
        "cik" => "1318605",
        "cusip" => "88160R101",
        "exchange" => "NASDAQ",
        "isDelisted" => false,
        ...
      }]}
  """
  def map_cik(cik, opts \\ []) do
    get_mapping("cik/#{cik}", opts)
  end

  @doc """
  Maps a ticker symbol to company details.

  ## Examples
      iex> SecioEx.MappingApi.map_ticker("TSLA", api_key: "your_api_key")
      {:ok, [%{
        "name" => "Tesla Inc",
        "ticker" => "TSLA",
        ...
      }]}
  """
  def map_ticker(ticker, opts \\ []) do
    get_mapping("ticker/#{ticker}", opts)
  end

  @doc """
  Maps a CUSIP to company details.

  ## Examples
      iex> SecioEx.MappingApi.map_cusip("88160R101", api_key: "your_api_key")
      {:ok, [%{
        "name" => "Tesla Inc",
        "cusip" => "88160R101",
        ...
      }]}
  """
  def map_cusip(cusip, opts \\ []) do
    get_mapping("cusip/#{cusip}", opts)
  end

  @doc """
  Maps a company name to company details.

  ## Examples
      iex> SecioEx.MappingApi.map_name("Tesla", api_key: "your_api_key")
      {:ok, [%{
        "name" => "Tesla Inc",
        ...
      }]}
  """
  def map_name(name, opts \\ []) do
    get_mapping("name/#{name}", opts)
  end

  @doc """
  Lists all companies on a given exchange.

  ## Examples
      iex> SecioEx.MappingApi.list_by_exchange("NASDAQ", api_key: "your_api_key")
      {:ok, [%{
        "name" => "Company1",
        "exchange" => "NASDAQ",
        ...
      }]}
  """
  def list_by_exchange(exchange, opts \\ []) do
    get_mapping("exchange/#{exchange}", opts)
  end

  @doc """
  Lists all companies in a given sector.

  ## Examples
      iex> SecioEx.MappingApi.list_by_sector("Technology", api_key: "your_api_key")
      {:ok, [%{
        "name" => "Company1",
        "sector" => "Technology",
        ...
      }]}
  """
  def list_by_sector(sector, opts \\ []) do
    get_mapping("sector/#{sector}", opts)
  end

  @doc """
  Lists all companies in a given industry.

  ## Examples
      iex> SecioEx.MappingApi.list_by_industry("Auto Manufacturers", api_key: "your_api_key")
      {:ok, [%{
        "name" => "Company1",
        "industry" => "Auto Manufacturers",
        ...
      }]}
  """
  def list_by_industry(industry, opts \\ []) do
    get_mapping("industry/#{industry}", opts)
  end

  # Private Functions

  defp get_mapping(path, opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    case use_auth_header?(opts) do
      true ->
        Req.get(URI.encode("#{@base_url}/#{path}"),
          headers: [{"Authorization", api_key}]
        )
        |> handle_response()

      false ->
        Req.get("#{@base_url}/#{path}",
          params: [token: api_key]
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
