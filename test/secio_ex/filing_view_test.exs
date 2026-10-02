defmodule SecioEx.FilingViewTest do
  use ExUnit.Case, async: true

  test "8-K item 1.05 is a critical cybersecurity filing" do
    filing = filing("8-K", ["Item 1.05: Material Cybersecurity Incidents"])

    assert SecioEx.FilingView.signal(filing) == :critical
    assert SecioEx.FilingView.badge(filing) == "CYBER"
    assert SecioEx.FilingView.plain(filing) =~ "CYBER"
    assert SecioEx.FilingView.plain(filing) =~ "CRIT"
  end

  test "8-K/A item 1.05 is critical when the item is only in the description" do
    filing = %{
      "formType" => "8-K/A",
      "ticker" => "MSFT",
      "companyName" => "Microsoft Corp (Filer)",
      "filedAt" => "2026-10-02T16:06:24-04:00",
      "description" => "Form 8-K/A - Current report - Item 1.05 Item 9.01"
    }

    assert SecioEx.FilingView.signal(filing) == :critical
    assert SecioEx.FilingView.badge(filing) == "CYBER"
    assert SecioEx.FilingView.company_name(filing) == "Microsoft Corp"
    assert SecioEx.FilingView.clock(filing) == "16:06:24"
  end

  test "item 1.05 outside an 8-K is not critical" do
    filing = %{
      "formType" => "10-K",
      "description" => "mentions Item 1.05 in another context",
      "ticker" => "AAPL"
    }

    refute SecioEx.FilingView.signal(filing) == :critical
    assert SecioEx.FilingView.badge(filing) == nil
  end

  test "other material 8-K items keep their rank" do
    assert SecioEx.FilingView.signal(filing("8-K", ["Item 4.02: Non-Reliance"])) == :critical
    assert SecioEx.FilingView.badge(filing("8-K", ["Item 4.02: Non-Reliance"])) == "RESTATE"
    assert SecioEx.FilingView.signal(filing("8-K", ["Item 1.03: Bankruptcy"])) == :critical
    assert SecioEx.FilingView.signal(filing("8-K", ["Item 2.02: Results of Operations"])) == :high

    assert SecioEx.FilingView.badge(filing("8-K", ["Item 2.02: Results of Operations"])) ==
             "EARNINGS"

    assert SecioEx.FilingView.signal(%{"formType" => "NT 10-K"}) == :critical
    assert SecioEx.FilingView.signal(%{"formType" => "4", "ticker" => "TSLA"}) == :high
    assert SecioEx.FilingView.signal(%{"formType" => "CORRESP"}) == :low
  end

  defp filing(form, items) do
    %{
      "formType" => form,
      "ticker" => "AAPL",
      "cik" => "320193",
      "companyName" => "Apple Inc.",
      "filedAt" => "2026-10-02T09:30:00-04:00",
      "items" => items,
      "linkToFilingDetails" => "https://www.sec.gov/Archives/example.htm"
    }
  end
end
