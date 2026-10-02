# SecioEx

Elixir client for the [sec-api.io](https://sec-api.io) APIs.

## Develop

This project is set up as a dev container (Elixir 1.18, OTP 27). Open the folder in the container. The host file `~/Desktop/sec.txt` is mounted read-only at `~/Desktop/sec.txt`.

## Live filing monitor

```bash
mix deps.get
mix secio.monitor
mix secio.monitor --forms 8-K,4 --watch AAPL,MSFT
mix secio.monitor --plain --for 30
```

The key is read from `--api-key-file`, `SEC_API_KEY`, or `~/Desktop/sec.txt`.

8-K item 1.05 (material cybersecurity incident) is flagged critical, along with bankruptcy (1.03), restatement (4.02), delisting (3.01), and change in control (5.01).

Dashboard keys: `q` quit, `a` alerts, `p` pause, `w` watch-only, `j`/`k` scroll, `r` back to live.

## Watch from an application

`SecioEx.Watch` opens one stream and runs many rules. The socket does not replay filings from before it connected. `:on` is called with one filing. A rule without `:on` sends `{:secio_ex, {:alert, name, filing}}` to `:subscriber`.

```elixir
children = [
  {SecioEx.Watch,
   rules: [
     [name: :cyber, items: ["1.05"], on: &MyApp.Alerts.cyber/1],
     [name: :insiders, form_types: ["4"], tickers: ["AAPL"], on: &MyApp.Alerts.form4/1]
   ]}
]
```

`:items` matches 8-K items, including `8-K/A`. `:min` sets a floor of `:low`, `:normal`, `:high`, or `:critical`. `:form_types`, `:tickers`, and `:ciks` use the same matching as the terminal monitor.

## HTTP APIs

Every call accepts `api_key:` or reads `SEC_API_KEY` / `~/Desktop/sec.txt`.

Lucene searches also accept `:from`, `:size`, and `:sort`. `stream/2` and `all/2` request the next page until a short page, an exact total, or offset 10,000. `:limit` stops earlier. One query cannot return more than 10,000 hits. Split a longer range with `SecioEx.Pages.date_windows/3` or `SecioEx.Pages.all_between/3` (`date_field: "releasedAt"` for enforcement releases). Each window still stops at 10,000.

`all/2` returns `{:ok, records}`. If a later page fails, it returns `{:error, %{reason: reason, records: records}}` and keeps the rows already fetched. `stream/2` raises `SecioEx.PageError`. The message is the HTTP status.

Full-text search uses `:page` (100 filings per page, at most 100 pages). `SecioEx.FullTextSearch.stream/2` walks those pages. N-PORT pages are 10 filings. SRO pages are 100.

| Module | What it calls |
| --- | --- |
| `SecioEx.QueryApi` | Filing search |
| `SecioEx.FullTextSearch` | Full-text search, paged by `:page` |
| `SecioEx.ExtractorApi` | One item from a 10-K, 10-Q, or 8-K. `:type` is `:text`, `:html`, `"text"`, or `"html"` |
| `SecioEx.DownloadApi` | Filing text from `edgar-mirror.sec-api.io`, and PDF. Accepts a path after `/data/` or a full EDGAR URL, including `/ix?doc=` |
| `SecioEx.MappingApi` | CIK, ticker, CUSIP, name |
| `SecioEx.XbrlToJson` | XBRL converted to JSON |
| `SecioEx.XbrlParser` | Read that JSON locally |
| `SecioEx.Form8K` | Structured 8-K search. Parsed objects include `item4_02` and `item5_02`. Item headings use `items:"Item 1.05"` |
| `SecioEx.Form144` | Form 144 proposed sales |
| `SecioEx.FormC` | Form C crowdfunding offerings |
| `SecioEx.Form13` | 13F holdings, 13F cover pages, 13D/13G. Each endpoint has its own `stream` and `all` |
| `SecioEx.FormD` | Form D offerings |
| `SecioEx.FormS1` | S-1 and 424B4 |
| `SecioEx.RegA` | Regulation A search, Form 1-A, 1-K, and 1-Z |
| `SecioEx.InsiderTradingApi` | Forms 3, 4, and 5 |
| `SecioEx.NportDataApi` | Form N-PORT, 10 filings per page |
| `SecioEx.NcenDataApi` | Form N-CEN, 50 filings per page |
| `SecioEx.NpxDataApi` | Form N-PX metadata, plus `voting_records/2` by accession number |
| `SecioEx.InvestmentAdviserAdvApi` | Form ADV firms, people, and schedules. Firm and individual search are paged |
| `SecioEx.ExecutiveCompensationApi` | Compensation by ticker or query |
| `SecioEx.DirectorsApi` | Directors and board members |
| `SecioEx.OutstandingSharesApi` | Public float |
| `SecioEx.SubsidiaryApi` | Exhibit 21 subsidiaries |
| `SecioEx.AaerDatabase` | Accounting and auditing enforcement releases |
| `SecioEx.EnforcementActions` | SEC enforcement actions, sorted by `releasedAt` |
| `SecioEx.LitigationReleases` | SEC litigation releases, sorted by `releasedAt` |
| `SecioEx.AdministrativeProceedings` | SEC administrative proceedings, sorted by `releasedAt` |
| `SecioEx.EdgarEntities` | EDGAR entities, sorted by `cikUpdatedAt` |
| `SecioEx.AuditFees` | Audit fees |
| `SecioEx.IngestionLog` | Daily EDGAR ingestion log, and the archive file index |
| `SecioEx.Datasets` | Bulk dataset index. `download/2` needs `:path` and streams files to disk |
| `SecioEx.SroFilings` | Exchange rule filings, 100 per page |
