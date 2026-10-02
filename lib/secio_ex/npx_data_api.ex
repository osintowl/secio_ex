defmodule SecioEx.NpxDataApi do
  require SecioEx.Search

  @moduledoc """
  Form N-PX proxy voting records.

  `search/2` posts to `/form-npx`. `voting_records/2` gets one filing at
  `/form-npx/:accessionNo`. The page size is at most 50.
  """

  @doc """
  Search N-PX filing metadata.

  ## Examples

      SecioEx.NpxDataApi.search("cik:0000842790", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-npx", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  @doc """
  Voting records for one accession number.

  `GET /form-npx/:accessionNo`
  """
  def voting_records(accession_no, opts \\ []) do
    accession_no = accession_no |> to_string() |> String.trim()

    if accession_no == "" do
      raise ArgumentError, "accession number is empty"
    end

    SecioEx.Client.get("/form-npx/#{SecioEx.Client.encode_segment(accession_no)}", opts)
  end

  SecioEx.Search.pages()
end
