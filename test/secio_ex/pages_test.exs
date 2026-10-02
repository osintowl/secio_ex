defmodule SecioEx.PagesTest do
  use ExUnit.Case, async: true

  @key "unit-test-key"

  test "an exact total is walked by from and size" do
    assert {:ok, rows} = SecioEx.Pages.all(&slice_page/1, size: 2)
    assert Enum.map(rows, & &1["id"]) == [0, 1, 2, 3, 4]
  end

  test "limit keeps a partial last page" do
    assert {:ok, rows} = SecioEx.Pages.all(&slice_page/1, size: 2, limit: 3)
    assert Enum.map(rows, & &1["id"]) == [0, 1, 2]
  end

  test "a gte total stops at the 10000 offset window" do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    fetch = fn [from: from, size: size] ->
      Agent.update(agent, fn seen ->
        if length(seen) > 4, do: raise("paged past the window")
        [from | seen]
      end)

      rows = Enum.map(1..size, fn i -> %{"id" => from + i} end)
      {:ok, %{"data" => rows, "total" => %{"value" => 10_000, "relation" => "gte"}}}
    end

    assert {:ok, rows} = SecioEx.Pages.all(fetch, size: 5_000)
    assert length(rows) == 10_000
    assert Enum.reverse(Agent.get(agent, & &1)) == [0, 5_000]
  end

  test "limit stops a gte query without another full page" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fetch = fn [from: _from, size: size] ->
      Agent.update(agent, &(&1 + 1))
      rows = Enum.map(1..size, &%{"id" => &1})
      {:ok, %{"data" => rows, "total" => %{"value" => 10_000, "relation" => "gte"}}}
    end

    assert {:ok, rows} = SecioEx.Pages.all(fetch, size: 2, limit: 3)
    assert length(rows) == 3
    assert Agent.get(agent, & &1) == 2
  end

  test "a bare list is a single page" do
    fetch = fn [from: from, size: _size] ->
      if from > 0, do: flunk("requested from #{from}")
      {:ok, [%{"id" => 1}, %{"id" => 2}]}
    end

    assert {:ok, [%{"id" => 1}, %{"id" => 2}]} = SecioEx.Pages.all(fetch, size: 2)
  end

  test "a missing relation is an exact total" do
    fetch = fn [from: from, size: _size] ->
      if from > 0, do: flunk("requested from #{from}")
      {:ok, %{"data" => [%{"id" => 1}, %{"id" => 2}], "total" => %{"value" => "2"}}}
    end

    assert {:ok, rows} = SecioEx.Pages.all(fetch, size: 2)
    assert length(rows) == 2
  end

  test "the first page error is returned unchanged" do
    assert {:error, %{status_code: 500, body: "nope"}} =
             SecioEx.Pages.all(fn _page -> {:error, %{status_code: 500, body: "nope"}} end,
               size: 2
             )
  end

  test "a later page error keeps the records already fetched" do
    fetch = fn [from: from, size: _size] ->
      if from == 0 do
        {:ok,
         %{"data" => [%{"id" => 1}, %{"id" => 2}], "total" => %{"value" => 4, "relation" => "eq"}}}
      else
        {:error, %{status_code: 429, body: "slow"}}
      end
    end

    assert {:error, %{reason: %{status_code: 429}, from: 2, records: records}} =
             SecioEx.Pages.all(fetch, size: 2)

    assert Enum.map(records, & &1["id"]) == [1, 2]
  end

  test "a stream raises the status and not the body" do
    stream =
      SecioEx.Pages.stream(fn _page -> {:error, %{status_code: 502, body: "secret-body"}} end,
        size: 1
      )

    assert_raise SecioEx.PageError, "HTTP 502", fn -> Enum.to_list(stream) end
  end

  test "full text pages stop on a short page" do
    fetch = fn [page: page] ->
      if page > 2, do: flunk("fetched page #{page}")

      rows =
        if page == 1 do
          Enum.map(1..100, &%{"id" => &1})
        else
          [%{"id" => 101}]
        end

      {:ok, %{"filings" => rows}}
    end

    assert {:ok, rows} = SecioEx.Pages.all_by_page(fetch, [])
    assert length(rows) == 101
  end

  test "page_size does not drop rows from a longer page" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fetch = fn [page: page] ->
      Agent.update(agent, &(&1 + 1))
      rows = if page == 1, do: Enum.map(1..5, &%{"id" => &1}), else: []
      {:ok, %{"filings" => rows, "total" => %{"relation" => "gte", "value" => 10_000}}}
    end

    assert {:ok, rows} = SecioEx.Pages.all_by_page(fetch, page_size: 2, limit: 20)
    assert Enum.map(rows, & &1["id"]) == [1, 2, 3, 4, 5]
    assert Agent.get(agent, & &1) == 2
  end

  test "full text stops after page 100" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fetch = fn [page: page] ->
      Agent.update(agent, &(&1 + 1))
      if page > 100, do: flunk("page #{page}")

      {:ok,
       %{
         "filings" => Enum.map(1..100, &%{"id" => &1}),
         "total" => %{"value" => 50_000, "relation" => "gte"}
       }}
    end

    assert {:ok, rows} = SecioEx.Pages.all_by_page(fetch, page_size: 100, limit: 10_000)
    assert length(rows) == 10_000
    assert Agent.get(agent, & &1) == 100
  end

  test "an offset at 10000 does not send a request" do
    assert {:ok, []} =
             SecioEx.Pages.all(fn _page -> flunk("requested") end, from: 10_000, size: 50)
  end

  test "date windows are inclusive and do not overlap" do
    assert SecioEx.Pages.date_windows("2024-01-01", "2024-01-10", 7) == [
             {"2024-01-01", "2024-01-07"},
             {"2024-01-08", "2024-01-10"}
           ]

    assert SecioEx.Pages.date_windows("2024-01-01", "2024-01-01") == [
             {"2024-01-01", "2024-01-01"}
           ]

    assert_raise ArgumentError, ~r/after/, fn ->
      SecioEx.Pages.date_windows("2024-02-01", "2024-01-01", 7)
    end

    assert_raise ArgumentError, ~r/at least 1/, fn ->
      SecioEx.Pages.date_windows("2024-01-01", "2024-01-02", 0)
    end

    assert_raise ArgumentError, ~r/YYYY-MM-DD/, fn ->
      SecioEx.Pages.date_windows("Jan 1", "2024-01-02", 7)
    end
  end

  test "all_between ands a date field onto each window" do
    search = fn query, opts ->
      send(self(), {:q, query, opts[:from], opts[:size], opts[:api_key]})
      {:ok, %{"data" => [], "total" => %{"value" => 0, "relation" => "eq"}}}
    end

    assert {:ok, []} =
             SecioEx.Pages.all_between(search, "ticker:AAPL",
               from_date: "2024-01-01",
               to_date: "2024-01-10",
               window_days: 7,
               size: 50,
               api_key: @key
             )

    assert_received {:q, "(ticker:AAPL) AND filedAt:[2024-01-01 TO 2024-01-07]", 0, 50, @key}
    assert_received {:q, "(ticker:AAPL) AND filedAt:[2024-01-08 TO 2024-01-10]", 0, 50, @key}

    assert {:ok, []} =
             SecioEx.Pages.all_between(search, "*",
               from_date: "2024-03-01",
               to_date: "2024-03-01",
               date_field: "releasedAt",
               size: 10
             )

    assert_received {:q, "releasedAt:[2024-03-01 TO 2024-03-01]", 0, 10, nil}
  end

  test "a failed later window keeps earlier records" do
    search = fn query, _opts ->
      if String.contains?(query, "2024-01-01") do
        {:ok, %{"data" => [%{"id" => 1}], "total" => %{"value" => 1, "relation" => "eq"}}}
      else
        {:error, %{status_code: 500}}
      end
    end

    assert {:error, %{reason: %{status_code: 500}, records: [%{"id" => 1}]}} =
             SecioEx.Pages.all_between(search, "*",
               from_date: "2024-01-01",
               to_date: "2024-01-10",
               window_days: 7,
               size: 10
             )
  end

  test "module pagination sends the endpoint page size" do
    plug = fn conn ->
      from = conn.body_params["from"]
      size = conn.body_params["size"]
      send(self(), {:page, conn.request_path, from, size, conn.body_params["query"]})
      rows = Enum.slice(for(id <- 0..4, do: %{"id" => id}), from, size)

      Req.Test.json(conn, %{
        "total" => %{"value" => 5, "relation" => "eq"},
        "data" => rows
      })
    end

    opts = [api_key: @key, plug: plug, size: 2]

    assert {:ok, rows} = SecioEx.Form144.all("ticker:AAPL", opts)
    assert Enum.map(rows, & &1["id"]) == [0, 1, 2, 3, 4]
    assert_received {:page, "/form-144", 0, 2, "ticker:AAPL"}
    assert_received {:page, "/form-144", 2, 2, "ticker:AAPL"}
    assert_received {:page, "/form-144", 4, 2, "ticker:AAPL"}

    nport = fn conn ->
      send(self(), {:nport, conn.body_params["size"]})

      Req.Test.json(conn, %{
        "data" => [%{"id" => 1}],
        "total" => %{"value" => 1, "relation" => "eq"}
      })
    end

    assert {:ok, [_]} = SecioEx.NportDataApi.all("*", api_key: @key, plug: nport, limit: 5)
    assert_received {:nport, 10}

    sro = fn conn ->
      send(self(), {:sro, conn.body_params["size"]})

      Req.Test.json(conn, %{
        "data" => [%{"id" => 1}],
        "total" => %{"value" => 1, "relation" => "eq"}
      })
    end

    assert {:ok, [_]} = SecioEx.SroFilings.all("sro:NASDAQ", api_key: @key, plug: sro, limit: 1)
    assert_received {:sro, 100}

    filings = fn conn ->
      send(self(), {:filings, conn.body_params["from"], Map.has_key?(conn.body_params, "size")})

      Req.Test.json(conn, %{
        "filings" => [%{"id" => 1}],
        "total" => %{"value" => 1, "relation" => "eq"}
      })
    end

    assert {:ok, [%{"id" => 1}]} =
             SecioEx.FullTextSearch.all("doubt", api_key: @key, plug: filings)

    assert_received {:filings, nil, false}

    assert_raise ArgumentError, ~r/YYYY-MM-DD/, fn ->
      SecioEx.IngestionLog.get("yesterday", api_key: @key, plug: filings)
    end

    refute_received {:filings, _, _}
  end

  defp slice_page(from: from, size: size) do
    rows = Enum.slice(for(id <- 0..4, do: %{"id" => id}), from, size)
    {:ok, %{"data" => rows, "total" => %{"value" => 5, "relation" => "eq"}}}
  end
end
