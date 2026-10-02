defmodule SecioEx.IngestionLog do
  @moduledoc """
  EDGAR index ingestion log and the daily archive index.

  `get/2` calls `GET /edgar-index/ingestion-log/YYYY-MM-DD`. The body has
  `total.value`, `data` (one object per accession), and `lastUpdatedAt`.

  `archive_index/1` calls `GET /edgar-index/archive/files/index.json`.
  Each entry has `key`, `updatedAt`, `size`, and `objectCount`.
  """

  @date ~r/^\d{4}-\d{2}-\d{2}$/

  @doc """
  Ingestion log for one UTC date, formatted `YYYY-MM-DD`.

  An invalid date raises before a request is sent.
  """
  def get(date, opts \\ []) do
    date = date |> to_string() |> String.trim()

    unless String.match?(date, @date) and match?({:ok, _}, Date.from_iso8601(date)) do
      raise ArgumentError, "date must be YYYY-MM-DD"
    end

    SecioEx.Client.get("/edgar-index/ingestion-log/#{date}", opts)
  end

  @doc "Index of the daily EDGAR archive files."
  def archive_index(opts \\ []) do
    SecioEx.Client.get("/edgar-index/archive/files/index.json", opts)
  end
end
