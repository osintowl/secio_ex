defmodule SecioEx.ScreenTest do
  use ExUnit.Case, async: true

  test "a cybersecurity 8-K is drawn in red with a CYBER badge" do
    filing = %{
      "formType" => "8-K",
      "ticker" => "AAPL",
      "cik" => "320193",
      "companyName" => "Apple Inc.",
      "filedAt" => "2026-10-02T16:06:24-04:00",
      "items" => ["Item 1.05: Material Cybersecurity Incidents"],
      "description" => "Form 8-K - Current report - Item 1.05",
      "linkToFilingDetails" => "https://www.sec.gov/Archives/edgar/data/320193/cyber.htm"
    }

    lines = SecioEx.Monitor.Screen.lines(state([filing]))
    assert length(lines) == 16
    visible = lines |> Enum.map(&strip/1) |> Enum.join("\n")

    assert visible =~ "CYBER"
    assert visible =~ "CRIT"
    assert visible =~ "AAPL"
    assert visible =~ "1.05"
    assert visible =~ "Apple Inc."

    cyber = Enum.find(lines, &(strip(&1) =~ "CYBER"))
    assert cyber =~ IO.ANSI.red()
  end

  test "alerts mode hides routine correspondence and keeps critical 8-Ks" do
    cyber = %{
      "formType" => "8-K",
      "ticker" => "AAPL",
      "companyName" => "Apple Inc.",
      "filedAt" => "2026-10-02T16:06:24-04:00",
      "items" => ["Item 1.05: Material Cybersecurity Incidents"]
    }

    letter = %{
      "formType" => "CORRESP",
      "ticker" => "ZZZZ",
      "companyName" => "Boring Corp",
      "filedAt" => "2026-10-02T16:01:00-04:00",
      "description" => "Correspondence"
    }

    visible =
      [cyber, letter]
      |> state()
      |> Map.put(:alerts_only, true)
      |> SecioEx.Monitor.Screen.lines()
      |> Enum.map(&strip/1)
      |> Enum.join("\n")

    assert visible =~ "Apple Inc."
    refute visible =~ "Boring Corp"
  end

  test "a watched ticker is highlighted and a pause freezes the list" do
    first = %{
      "formType" => "10-Q",
      "ticker" => "MSFT",
      "companyName" => "Microsoft Corp",
      "filedAt" => "2026-10-02T12:00:00-04:00"
    }

    second = %{
      "formType" => "4",
      "ticker" => "TSLA",
      "companyName" => "Tesla Inc",
      "filedAt" => "2026-10-02T12:05:00-04:00"
    }

    watch = SecioEx.Watchlist.new("MSFT")
    base = state([first]) |> Map.put(:watch, watch) |> Map.put(:watch_label, "MSFT")
    lines = SecioEx.Monitor.Screen.lines(base)
    watched = Enum.find(lines, &(strip(&1) =~ "Microsoft"))
    assert watched =~ IO.ANSI.magenta()

    paused =
      base
      |> Map.put(:paused, true)
      |> Map.put(:frozen, [first])
      |> Map.put(:recent, [second, first])

    frozen = paused |> SecioEx.Monitor.Screen.lines() |> Enum.map(&strip/1) |> Enum.join("\n")
    assert frozen =~ "Microsoft Corp"
    refute frozen =~ "Tesla Inc"
    assert frozen =~ "PAUSED"
  end

  defp state(recent) do
    %{
      cols: 100,
      rows: 16,
      scroll: 0,
      paused: false,
      frozen: nil,
      alerts_only: false,
      watch_only: false,
      watch: SecioEx.Watchlist.new(nil),
      watch_label: "",
      recent: recent,
      status: :live,
      uptime_s: 90,
      filtered: false,
      seen: length(recent),
      critical: Enum.count(recent, &(SecioEx.FilingView.signal(&1) == :critical)),
      reconnects: 0,
      by_form: %{},
      reason: nil,
      note: nil
    }
  end

  defp strip(line), do: String.replace(line, ~r/\e\[[0-9;]*m/, "")
end
