defmodule SecioEx do
  @moduledoc """
  Client for the [sec-api.io](https://sec-api.io) APIs.

  ## Live monitor

      mix secio.monitor
      mix secio.monitor --forms 8-K,4 --watch AAPL,MSFT

  The API key is read from `SEC_API_KEY` or `~/Desktop/sec.txt`.

  ## Stream API

      {:ok, pid} = SecioEx.StreamApi.start_link(subscriber: self())

      {:ok, _pid} =
        SecioEx.Watch.start_link(
          rules: [
            [name: :cyber, items: ["1.05"], on: &MyApp.Alerts.cyber/1]
          ]
        )

  `SecioEx.Watch` is one socket and many rules. A callback runs in its own process.

  ## Filing and dataset APIs

  The key is read from `:api_key`, `:api_key_file`, `SEC_API_KEY`, or
  `~/Desktop/sec.txt`.

  Lucene searches expose `stream/2` and `all/2`. One query window stops at
  10,000 hits. `SecioEx.Pages.date_windows/3` splits a longer date range.
  Full-text search walks `:page` instead, 100 filings per page.

    * `SecioEx.QueryApi` — filing search
    * `SecioEx.FullTextSearch` — full-text search
    * `SecioEx.ExtractorApi` — one section of a 10-K, 10-Q, or 8-K
    * `SecioEx.DownloadApi` — filing text from the EDGAR mirror, and PDF
    * `SecioEx.MappingApi` — CIK, ticker, CUSIP, and company names
    * `SecioEx.XbrlToJson` and `SecioEx.XbrlParser` — financial statements
    * `SecioEx.Form8K` — structured 8-K items (`item4_02`, `item5_02`, and the `items` list)
    * `SecioEx.Form144` — Form 144
    * `SecioEx.FormC` — Form C
    * `SecioEx.Form13` — 13F holdings, 13F cover pages, and 13D/13G
    * `SecioEx.FormD` — exempt offerings
    * `SecioEx.FormS1` — S-1 and 424B4
    * `SecioEx.RegA` — Regulation A search, Form 1-A, 1-K, and 1-Z
    * `SecioEx.InsiderTradingApi` — Forms 3, 4, and 5
    * `SecioEx.NportDataApi` — Form N-PORT
    * `SecioEx.NcenDataApi` — Form N-CEN
    * `SecioEx.NpxDataApi` — Form N-PX metadata and voting records
    * `SecioEx.InvestmentAdviserAdvApi` — Form ADV
    * `SecioEx.ExecutiveCompensationApi` — compensation
    * `SecioEx.DirectorsApi` — directors and board members
    * `SecioEx.OutstandingSharesApi` — public float
    * `SecioEx.SubsidiaryApi` — Exhibit 21
    * `SecioEx.AaerDatabase` — accounting and auditing enforcement releases
    * `SecioEx.EnforcementActions` — enforcement actions
    * `SecioEx.LitigationReleases` — litigation releases
    * `SecioEx.AdministrativeProceedings` — administrative proceedings
    * `SecioEx.EdgarEntities` — EDGAR entities
    * `SecioEx.AuditFees` — audit fees
    * `SecioEx.IngestionLog` — daily EDGAR ingestion log
    * `SecioEx.Datasets` — bulk dataset index and file download
    * `SecioEx.SroFilings` — exchange rule filings
  """
end
