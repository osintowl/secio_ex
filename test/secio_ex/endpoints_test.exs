defmodule SecioEx.EndpointsTest do
  use ExUnit.Case, async: true

  @key "unit-test-key"

  test "dataset endpoints post a lucene query with their page size and sort" do
    for {fun, path, size, sort_field} <- datasets() do
      assert {:ok, %{"ok" => true}} = fun.("ticker:AAPL", key_opts())
      assert_received {:http, "POST", "api.sec-api.io", request_path, query, body, headers}
      assert request_path == path or (path == "/" and request_path == nil)
      assert query["token"] == nil
      assert auth_header(headers) == @key
      assert body["query"] == "ticker:AAPL"
      assert body["from"] == 0
      assert body["size"] == size
      assert body["sort"] == [%{sort_field => %{"order" => "desc"}}]
    end
  end

  test "query helpers keep their paths and queries" do
    assert {:ok, _} = SecioEx.QueryApi.search_by_ticker("AAPL", key_opts())
    assert_received {:http, "POST", "api.sec-api.io", request_path, _query, body, _}
    assert request_path in [nil, "/"]
    assert body["query"] == "ticker:AAPL"
    assert body["size"] == 50

    assert {:ok, _} =
             SecioEx.FullTextSearch.search("doubt", key_opts() ++ [form_types: ["8-K"], page: 2])

    assert_received {:http, "POST", "api.sec-api.io", "/full-text-search", _, body, _}
    assert body["query"] == "doubt"
    assert body["formTypes"] == ["8-K"]
    assert body["page"] == "2"

    assert {:ok, _} = SecioEx.InsiderTradingApi.by_ticker("aapl", key_opts())
    assert_received {:http, "POST", _, "/insider-trading", _, body, _}
    assert body["query"] == "issuer.tradingSymbol:AAPL"

    assert {:ok, _} = SecioEx.Form8K.search_item("1.05", key_opts())
    assert_received {:http, "POST", _, "/form-8k", _, body, _}
    assert body["query"] == ~s(items:"Item 1.05")

    assert {:ok, _} = SecioEx.FormD.by_issuer("Foo \"Bar\"", key_opts())
    assert_received {:http, "POST", _, "/form-d", _, body, _}
    assert body["query"] == ~s(primaryIssuer.entityName:"Foo \\"Bar\\"")

    assert {:ok, _} = SecioEx.DirectorsApi.search_by_ticker("AAPL", key_opts())
    assert_received {:http, "POST", _, "/directors-and-board-members", _, body, _}
    assert body["query"] == "ticker:AAPL"
  end

  test "structured 8-K item numbers map onto dataset fields" do
    assert SecioEx.Form8K.item_field("4.02") == "item4_02"
    assert SecioEx.Form8K.item_field("Item 1.05") == "item1_05"
    assert SecioEx.Form8K.item_field("item4_02") == "item4_02"
    assert SecioEx.Form8K.item_label("4.02") == "Item 4.02"
    assert SecioEx.Form8K.item_label("item4_02") == "Item 4.02"
    assert SecioEx.Form8K.item_label("Item 1.05") == "Item 1.05"
    assert_raise ArgumentError, ~r/empty/, fn -> SecioEx.Form8K.item_field("  ") end
  end

  test "get endpoints encode the path and require their arguments" do
    assert {:ok, _} = SecioEx.ExecutiveCompensationApi.by_ticker("aapl", key_opts())
    assert_received {:http, "GET", "api.sec-api.io", "/compensation/AAPL", query, _, headers}
    assert query["token"] == nil
    assert auth_header(headers) == @key
    assert accept_encoding(headers) =~ "gzip"

    assert {:ok, _} = SecioEx.OutstandingSharesApi.by_ticker("AAPL", key_opts())
    assert_received {:http, "GET", _, "/float", query, _, _}
    assert query["ticker"] == "AAPL"

    assert {:ok, _} = SecioEx.OutstandingSharesApi.by_cik(320_193, key_opts())
    assert_received {:http, "GET", _, "/float", query, _, _}
    assert query["cik"] == "320193"

    assert {:ok, _} = SecioEx.InvestmentAdviserAdvApi.private_funds("801-123", key_opts())
    assert_received {:http, "GET", _, "/form-adv/schedule-d-7-b-1/801-123", _, _, _}

    assert {:ok, _} = SecioEx.InvestmentAdviserAdvApi.brochures(12_345, key_opts())
    assert_received {:http, "GET", _, "/form-adv/brochures/12345", _, _, _}

    assert {:ok, _} =
             SecioEx.MappingApi.map_name("Tesla Inc", key_opts() ++ [use_auth_header: false])

    assert_received {:http, "GET", _, path, query, _, headers}
    assert path in ["/mapping/name/Tesla Inc", "/mapping/name/Tesla%20Inc"]
    refute path =~ "%2520"
    assert query["token"] == @key
    assert auth_header(headers) == nil

    assert {:ok, _} =
             SecioEx.XbrlToJson.convert(
               key_opts() ++ [htm_url: "https://www.sec.gov/example-10k.htm"]
             )

    assert_received {:http, "GET", _, "/xbrl-to-json", query, _, _}
    assert query["htm-url"] == "https://www.sec.gov/example-10k.htm"
    assert query["xbrl-url"] == nil

    assert {:ok, _} =
             SecioEx.DownloadApi.download("815094/000/file.htm", key_opts())

    assert_received {:http, "GET", "edgar-mirror.sec-api.io", "/815094/000/file.htm", _, _,
                     headers}

    assert auth_header(headers) == @key

    filing = "https://www.sec.gov/Archives/edgar/data/1/file.htm"

    assert {:ok, _} = SecioEx.DownloadApi.generate_pdf(filing, key_opts())
    assert_received {:http, "GET", "api.sec-api.io", "/filing-reader", query, _, headers}
    assert query["token"] == @key
    assert query["url"] == filing
    assert auth_header(headers) == nil

    assert {:ok, _} =
             SecioEx.ExtractorApi.extract(
               "https://www.sec.gov/Archives/example-8k.htm",
               "1-1",
               key_opts()
             )

    assert_received {:http, "GET", _, "/extractor", query, _, _}
    assert query["item"] == "1-1"
    assert query["type"] == "text"
    assert query["url"] =~ "example-8k.htm"

    assert {:ok, _} =
             SecioEx.ExtractorApi.extract(
               "https://www.sec.gov/Archives/example-8k.htm",
               "1-1",
               key_opts() ++ [type: "html"]
             )

    assert_received {:http, "GET", _, "/extractor", query, _, _}
    assert query["type"] == "html"
  end

  test "download accepts an EDGAR url and rejects a path outside the archives" do
    filing = "https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl.htm"
    viewer = "https://www.sec.gov/ix?doc=/Archives/edgar/data/320193/000032019323000106/aapl.htm"

    xhtml =
      "https://www.sec.gov/ix.xhtml?doc=/Archives/edgar/data/320193/000032019323000106/aapl.htm"

    assert SecioEx.DownloadApi.archive_path("815094/000/file.htm") == "/815094/000/file.htm"
    assert SecioEx.DownloadApi.archive_path(filing) == "/320193/000032019323000106/aapl.htm"
    assert SecioEx.DownloadApi.archive_path(viewer) == "/320193/000032019323000106/aapl.htm"
    assert SecioEx.DownloadApi.archive_path(xhtml) == "/320193/000032019323000106/aapl.htm"

    assert {:ok, _} = SecioEx.DownloadApi.download(viewer, key_opts())

    assert_received {:http, "GET", "edgar-mirror.sec-api.io",
                     "/320193/000032019323000106/aapl.htm", _, _, _}

    assert_raise ArgumentError, ~r/EDGAR/, fn ->
      SecioEx.DownloadApi.download("https://example.com/not-edgar.htm", key_opts())
    end

    assert_raise ArgumentError, ~r/invalid EDGAR path/, fn ->
      SecioEx.DownloadApi.archive_path("815094/../secret.htm")
    end

    refute_received {:http, _, _, _, _, _, _}
  end

  test "extractor rejects a return type other than text or html" do
    assert {:error, "Invalid return type"} =
             SecioEx.ExtractorApi.extract(
               "https://www.sec.gov/Archives/example-8k.htm",
               "1-1",
               key_opts() ++ [type: "HTML"]
             )

    refute_received {:http, _, _, _, _, _, _}
  end

  test "ingestion, n-px votes, and the dataset index use their get paths" do
    assert {:ok, _} = SecioEx.IngestionLog.get("2026-10-01", key_opts())

    assert_received {:http, "GET", "api.sec-api.io", "/edgar-index/ingestion-log/2026-10-01", _,
                     _, _}

    assert {:ok, _} = SecioEx.IngestionLog.archive_index(key_opts())

    assert_received {:http, "GET", _, "/edgar-index/archive/files/index.json", _, _, _}

    assert {:ok, _} = SecioEx.NpxDataApi.voting_records("000123-24-000001", key_opts())
    assert_received {:http, "GET", _, "/form-npx/000123-24-000001", _, _, _}

    assert {:ok, _} = SecioEx.Datasets.list(key_opts())
    assert_received {:http, "GET", "api.sec-api.io", "/bulk/indicies/master/index.json", _, _, _}

    assert {:ok, _} = SecioEx.Datasets.details("form-d", key_opts())
    assert_received {:http, "GET", _, "/datasets/form-d.json", _, _, _}

    assert {:ok, _} = SecioEx.EnforcementActions.by_ticker("iep", key_opts())
    assert_received {:http, "POST", _, "/sec-enforcement-actions", _, body, _}
    assert body["query"] == "entities.ticker:IEP"
    assert body["sort"] == [%{"releasedAt" => %{"order" => "desc"}}]
  end

  test "dataset download plans files, skips a finished one, and streams the rest" do
    details = %{
      "containers" => [
        %{"key" => "2024/a.jsonl.gz", "downloadUrl" => "https://files.test/a", "size" => 5},
        %{"key" => "2024/b.jsonl.gz", "downloadUrl" => "https://files.test/b", "size" => 4}
      ]
    }

    assert {:ok, files} = SecioEx.Datasets.plan(details)
    assert Enum.map(files, & &1.key) == ["2024/a.jsonl.gz", "2024/b.jsonl.gz"]

    assert {:error, %{reason: "dataset has no containers"}} =
             SecioEx.Datasets.plan(%{"containers" => []})

    assert {:error, %{reason: :invalid_key, key: "../x"}} =
             SecioEx.Datasets.plan(%{
               "containers" => [%{"key" => "../x", "downloadUrl" => "https://files.test/x"}]
             })

    assert {:ok, [%{key: "form-d.zip", url: "https://files.test/sets/form-d.zip"}]} =
             SecioEx.Datasets.plan(
               %{"datasetDownloadUrl" => "https://files.test/sets/form-d.zip"},
               :zip
             )

    dir = Path.join(System.tmp_dir!(), "secio-datasets-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    assert_raise ArgumentError, ~r/pass :path/, fn ->
      SecioEx.Datasets.download(details, api_key: @key)
    end

    ready = Path.join(dir, "2024/a.jsonl.gz")
    File.mkdir_p!(Path.dirname(ready))
    File.write!(ready, "hello")

    plug = fn conn ->
      send(self(), {:download, conn.host, conn.request_path, conn.query_params["token"]})

      body = if conn.request_path == "/b", do: "four", else: "nope"

      conn
      |> Plug.Conn.put_resp_content_type("application/octet-stream")
      |> Plug.Conn.send_resp(200, body)
    end

    assert {:ok, paths} =
             SecioEx.Datasets.download(details, path: dir, api_key: @key, plug: plug)

    assert paths == [ready, Path.join(dir, "2024/b.jsonl.gz")]
    assert File.read!(Path.join(dir, "2024/b.jsonl.gz")) == "four"
    assert_received {:download, "files.test", "/b", @key}
    refute_received {:download, _, "/a", _}

    mismatch = %{
      "containers" => [
        %{"key" => "c.bin", "downloadUrl" => "https://files.test/c", "size" => 2}
      ]
    }

    assert {:error, %{reason: :size_mismatch, expected: 2, actual: 4}} =
             SecioEx.Datasets.download(mismatch, path: dir, api_key: @key, plug: plug)

    refute File.exists?(Path.join(dir, "c.bin"))
    refute File.exists?(Path.join(dir, "c.bin.partial"))
  end

  test "missing arguments raise before a request" do
    assert_raise ArgumentError, ~r/pass :ticker or :cik/, fn ->
      SecioEx.OutstandingSharesApi.get(key_opts())
    end

    refute_received {:http, _, _, _, _, _, _}

    assert_raise ArgumentError, ~r/not both/, fn ->
      SecioEx.OutstandingSharesApi.get(
        ticker: "AAPL",
        cik: "320193",
        api_key: @key,
        plug: recorder()
      )
    end

    assert_raise ArgumentError, ~r/one of/, fn ->
      SecioEx.XbrlToJson.convert(api_key: @key, plug: recorder())
    end

    assert_raise ArgumentError, ~r/only one/, fn ->
      SecioEx.XbrlToJson.convert(
        htm_url: "https://example.test/a.htm",
        accession_no: "0001-1",
        api_key: @key,
        plug: recorder()
      )
    end

    assert_raise ArgumentError, ~r/empty/, fn ->
      SecioEx.InvestmentAdviserAdvApi.direct_owners("  ", api_key: @key, plug: recorder())
    end

    assert_raise ArgumentError, ~r/empty/, fn ->
      SecioEx.ExecutiveCompensationApi.by_ticker(" ", api_key: @key, plug: recorder())
    end
  end

  test "a 404 is returned once and a leaked key is removed from the error" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    plug = fn conn ->
      Agent.update(agent, &(&1 + 1))

      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(404, "missing #{@key}")
    end

    assert {:error, %{status_code: 404, body: "missing [redacted]"}} =
             SecioEx.Client.get("/float", api_key: @key, plug: plug)

    assert Agent.get(agent, & &1) == 1
  end

  defp datasets do
    filed = "filedAt"

    [
      {&SecioEx.QueryApi.search/2, "/", 50, filed},
      {&SecioEx.AaerDatabase.search/2, "/aaers", 50, "dateTime"},
      {&SecioEx.Form13.holdings/2, "/form-13f/holdings", 50, filed},
      {&SecioEx.Form13.cover_pages/2, "/form-13f/cover-pages", 50, filed},
      {&SecioEx.Form13.beneficial_ownership/2, "/form-13d-13g", 50, filed},
      {&SecioEx.Form8K.search/2, "/form-8k", 50, filed},
      {&SecioEx.FormD.search/2, "/form-d", 50, filed},
      {&SecioEx.FormS1.search/2, "/form-s1-424b4", 50, filed},
      {&SecioEx.InsiderTradingApi.search/2, "/insider-trading", 50, filed},
      {&SecioEx.NportDataApi.search/2, "/form-nport", 10, filed},
      {&SecioEx.InvestmentAdviserAdvApi.search_firms/2, "/form-adv/firm", 50, filed},
      {&SecioEx.InvestmentAdviserAdvApi.search_individuals/2, "/form-adv/individual", 50, filed},
      {&SecioEx.ExecutiveCompensationApi.search/2, "/compensation", 50, filed},
      {&SecioEx.SubsidiaryApi.search/2, "/subsidiaries", 50, filed},
      {&SecioEx.SroFilings.search/2, "/sro", 100, "issueDate"},
      {&SecioEx.DirectorsApi.search/2, "/directors-and-board-members", 50, filed},
      {&SecioEx.Form144.search/2, "/form-144", 50, filed},
      {&SecioEx.FormC.search/2, "/form-c", 50, filed},
      {&SecioEx.NcenDataApi.search/2, "/form-ncen", 50, filed},
      {&SecioEx.NpxDataApi.search/2, "/form-npx", 50, filed},
      {&SecioEx.RegA.search/2, "/reg-a/search", 50, filed},
      {&SecioEx.RegA.form_1a/2, "/reg-a/form-1a", 50, filed},
      {&SecioEx.RegA.form_1k/2, "/reg-a/form-1k", 50, filed},
      {&SecioEx.RegA.form_1z/2, "/reg-a/form-1z", 50, filed},
      {&SecioEx.EnforcementActions.search/2, "/sec-enforcement-actions", 50, "releasedAt"},
      {&SecioEx.LitigationReleases.search/2, "/sec-litigation-releases", 50, "releasedAt"},
      {&SecioEx.AdministrativeProceedings.search/2, "/sec-administrative-proceedings", 50,
       "releasedAt"},
      {&SecioEx.EdgarEntities.search/2, "/edgar-entities", 50, "cikUpdatedAt"},
      {&SecioEx.AuditFees.search/2, "/audit-fees", 50, filed}
    ]
  end

  defp key_opts, do: [api_key: @key, plug: recorder()]

  defp recorder do
    fn conn ->
      send(
        self(),
        {:http, conn.method, conn.host, conn.request_path, conn.query_params, conn.body_params,
         conn.req_headers}
      )

      Req.Test.json(conn, %{ok: true})
    end
  end

  defp auth_header(headers) do
    header(headers, "authorization")
  end

  defp accept_encoding(headers) do
    header(headers, "accept-encoding")
  end

  defp header(headers, wanted) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(to_string(name)) == wanted, do: value
    end)
  end
end
