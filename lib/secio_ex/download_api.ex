# lib/secio_ex/download_api.ex
defmodule SecioEx.DownloadApi do
  @download_url "https://archive.sec-api.io"
  @pdf_url "https://api.sec-api.io/filing-reader"

  @moduledoc """
  Generate Pdf's and download filings and files from the SEC database. 
  """

  @doc """
  Downloads a filing or exhibit from SEC EDGAR.

  ## Parameters
    - path: The path to the file on SEC EDGAR (after /data/)
    - opts: Keyword list of options including :api_key

  ## Examples
      iex> SecioEx.DownloadApi.download(
        "815094/000156459021006205/abmd-8k_20210211.htm",
        api_key: "your_api_key"
      )
      {:ok, "filing content..."}
  """
  def download(path, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)

    Req.get("#{@download_url}/#{path}",
      headers: [{"Authorization", api_key}]
    )
    |> handle_response()
  end

  @doc """
  Generates a PDF from a filing or exhibit.

  ## Parameters
    - url: The full SEC.gov URL of the filing or exhibit
    - opts: Keyword list of options including :api_key

  ## Examples
      iex> SecioEx.DownloadApi.generate_pdf(
        "https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm",
        api_key: "your_api_key"
      )
      {:ok, <<PDF content...>>}
  """
  def generate_pdf(url, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)

    Req.get(@pdf_url,
      params: [
        token: api_key,
        url: url
      ]
    )
    |> handle_pdf_response()
  end

  @doc """
  Downloads a filing by CIK and accession number.

  ## Parameters
    - cik: The CIK number (without leading zeros)
    - accession_no: The accession number (with hyphens removed)
    - filename: The filename of the document
    - opts: Keyword list of options including :api_key

  ## Examples
      iex> SecioEx.DownloadApi.download_by_identifiers(
        "815094",
        "000156459021006205",
        "abmd-8k_20210211.htm",
        api_key: "your_api_key"
      )
      {:ok, "filing content..."}
  """
  def download_by_identifiers(cik, accession_no, filename, opts \\ []) do
    path = "#{cik}/#{accession_no}/#{filename}"
    download(path, opts)
  end

  # Private Functions

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, %{status_code: status, body: body}}
  end

  defp handle_response({:error, error}) do
    {:error, error}
  end

  defp handle_pdf_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_pdf_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, %{status_code: status, body: body}}
  end

  defp handle_pdf_response({:error, error}) do
    {:error, error}
  end
end
