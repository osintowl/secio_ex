defmodule SecioEx.DownloadApi do
  @mirror "https://edgar-mirror.sec-api.io"
  @pdf_url "https://api.sec-api.io/filing-reader"

  @moduledoc """
  Download filings from the EDGAR mirror and render them as PDFs.

  `download/2` accepts a path after `/data/` or a full EDGAR URL. Viewer
  prefixes `/ix?doc=/` and `/ix.xhtml?doc=/` are removed before the path is
  taken from `/edgar/data/`. PDFs still come from `/filing-reader`.
  """

  @doc """
  Downloads a filing or exhibit from SEC EDGAR.

  ## Parameters
    - path: A path after `/data/`, or a `sec.gov` archives URL
    - opts: Keyword list of options including :api_key

  ## Examples
      iex> SecioEx.DownloadApi.download(
        "815094/000156459021006205/abmd-8k_20210211.htm",
        api_key: "your_api_key"
      )
      {:ok, "filing content..."}
  """
  def download(path, opts \\ []) do
    SecioEx.Client.get_absolute(@mirror <> archive_path(path), opts)
  end

  @doc """
  Mirror path for an EDGAR file.

  A bare path is returned with a leading slash. An archives URL, including
  the `/ix?doc=` viewer form, is reduced to the path after `/edgar/data/`.
  """
  def archive_path(input) when is_binary(input) do
    path =
      input
      |> String.trim()
      |> String.replace("/ix.xhtml?doc=/", "/")
      |> String.replace("/ix?doc=/", "/")
      |> drop_suffix("#")
      |> drop_suffix("?")

    relative =
      cond do
        path == "" ->
          raise ArgumentError, "invalid EDGAR path"

        String.contains?(path, "/edgar/data/") ->
          path |> String.split("/edgar/data/", parts: 2) |> Enum.at(1)

        String.contains?(path, "://") ->
          raise ArgumentError, "not an EDGAR archives URL"

        true ->
          path
      end

    relative =
      relative
      |> drop_suffix("&")
      |> String.trim()
      |> String.trim_leading("/")

    if relative == "" or unsafe_path?(relative) do
      raise ArgumentError, "invalid EDGAR path"
    end

    "/" <> relative
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
    opts =
      opts
      |> Keyword.put(:auth, :query)
      |> Keyword.put(:params, url: url)

    SecioEx.Client.get_absolute(@pdf_url, opts)
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
    download("#{cik}/#{accession_no}/#{filename}", opts)
  end

  defp drop_suffix(value, marker) do
    value |> String.split(marker, parts: 2) |> hd()
  end

  defp unsafe_path?(path) do
    lowered = String.downcase(path)

    String.contains?(path, "..") or String.contains?(lowered, "%2e%2e") or
      String.contains?(path, "\\")
  end
end
