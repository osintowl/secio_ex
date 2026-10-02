defmodule SecioEx.XbrlParserTest do
  use ExUnit.Case, async: true

  alias SecioEx.XbrlParser

  @filing %{
    "CoverPage" => %{
      "DocumentType" => "10-K",
      "TradingSymbol" => [
        %{"value" => "AAPL", "unitRef" => "shares", "decimals" => nil}
      ]
    },
    "StatementsOfIncome" => %{
      "RevenueFromContractWithCustomerExcludingAssessedTax" => [
        %{
          "value" => "274515000000",
          "unitRef" => "usd",
          "decimals" => "-6",
          "period" => %{"startDate" => "2019-09-29", "endDate" => "2020-09-26"}
        },
        %{
          "value" => "260174000000",
          "unitRef" => "usd",
          "decimals" => "-6",
          "period" => %{"startDate" => "2018-09-30", "endDate" => "2019-09-28"}
        }
      ],
      "NetIncomeLoss" => %{
        "value" => "57411000000",
        "unitRef" => "usd",
        "decimals" => "-6",
        "period" => %{"endDate" => "2020-09-26"}
      }
    }
  }

  test "reads canonical statements and ignores missing ones" do
    assert XbrlParser.cover_page(@filing) == @filing["CoverPage"]
    assert XbrlParser.income(@filing) == @filing["StatementsOfIncome"]
    assert XbrlParser.balance_sheet(@filing) == nil
    assert XbrlParser.cash_flows(@filing) == nil

    assert Map.keys(XbrlParser.statements(@filing)) |> Enum.sort() ==
             ["CoverPage", "StatementsOfIncome"]
  end

  test "flattens concept lists, a single fact, and a cover-page scalar" do
    income = XbrlParser.facts(XbrlParser.income(@filing))

    revenue = Enum.filter(income, &(&1.concept =~ "Revenue"))
    assert length(revenue) == 2

    latest = hd(revenue)

    assert latest == %{
             concept: "RevenueFromContractWithCustomerExcludingAssessedTax",
             value: "274515000000",
             period: %{"startDate" => "2019-09-29", "endDate" => "2020-09-26"},
             unit: "usd",
             decimals: "-6"
           }

    assert XbrlParser.concept(XbrlParser.income(@filing), "NetIncomeLoss") == [
             %{
               concept: "NetIncomeLoss",
               value: "57411000000",
               period: %{"endDate" => "2020-09-26"},
               unit: "usd",
               decimals: "-6"
             }
           ]

    assert XbrlParser.concept(XbrlParser.cover_page(@filing), "DocumentType") == [
             %{concept: "DocumentType", value: "10-K", period: nil, unit: nil, decimals: nil}
           ]
  end
end
