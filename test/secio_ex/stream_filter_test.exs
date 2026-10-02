defmodule SecioEx.StreamFilterTest do
  use ExUnit.Case, async: true

  test "8-K matches the base form and its amendment only" do
    filter = SecioEx.StreamFilter.new(form_types: "8-K")

    assert SecioEx.StreamFilter.match?(%{"formType" => "8-K"}, filter)
    assert SecioEx.StreamFilter.match?(%{"formType" => "8-k/a"}, filter)
    refute SecioEx.StreamFilter.match?(%{"formType" => "8-K12B"}, filter)
    refute SecioEx.StreamFilter.match?(%{"formType" => "10-K"}, filter)
  end

  test "form 4 does not match 424B4" do
    filter = SecioEx.StreamFilter.new(form_types: "4")

    assert SecioEx.StreamFilter.match?(%{"formType" => "4"}, filter)
    assert SecioEx.StreamFilter.match?(%{"formType" => "4/A"}, filter)
    refute SecioEx.StreamFilter.match?(%{"formType" => "424B4"}, filter)
    refute SecioEx.StreamFilter.match?(%{"formType" => "40-F"}, filter)
  end

  test "ticker and CIK filters ignore leading zeros and entity CIKs" do
    by_ticker = SecioEx.StreamFilter.new(tickers: "aapl")

    assert SecioEx.StreamFilter.match?(
             %{"formType" => "8-K", "ticker" => "AAPL", "cik" => "320193"},
             by_ticker
           )

    refute SecioEx.StreamFilter.match?(
             %{"formType" => "8-K", "ticker" => "MSFT", "cik" => "789019"},
             by_ticker
           )

    cik_only = SecioEx.StreamFilter.new(ciks: "789019")

    assert SecioEx.StreamFilter.match?(
             %{
               "formType" => "4",
               "ticker" => "",
               "cik" => "1",
               "entities" => [%{"cik" => "0000789019"}]
             },
             cik_only
           )
  end

  test "an empty filter keeps every filing" do
    filter = SecioEx.StreamFilter.new([])
    assert SecioEx.StreamFilter.match?(%{"formType" => "CORRESP"}, filter)
    refute SecioEx.StreamFilter.active?(filter)
  end
end
