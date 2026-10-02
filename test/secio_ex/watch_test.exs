defmodule SecioEx.WatchTest do
  use ExUnit.Case, async: true

  @key "unit-test-key"

  test "item 1.05 matches only an 8-K that carries that item" do
    rule = [name: :cyber, items: ["1.05"]]

    assert SecioEx.Watch.matches?(rule, eight_k(["1.05"]))
    assert SecioEx.Watch.matches?(rule, Map.put(eight_k(["1.05"]), "formType", "8-K/A"))
    assert SecioEx.Watch.matches?([name: :cyber, items: "item 1.05, item4_02"], eight_k(["4.02"]))
    refute SecioEx.Watch.matches?(rule, eight_k(["2.02"]))
    refute SecioEx.Watch.matches?(rule, %{"formType" => "10-K", "description" => "Item 1.05"})
  end

  test "min is a floor on the filing signal" do
    critical = [name: :alerts, min: :critical]
    high = [name: :alerts, min: :high]

    assert SecioEx.Watch.matches?(critical, %{"formType" => "NT 10-K"})
    assert SecioEx.Watch.matches?(critical, eight_k(["1.05"]))
    refute SecioEx.Watch.matches?(critical, eight_k([]))
    refute SecioEx.Watch.matches?(critical, %{"formType" => "CORRESP"})

    assert SecioEx.Watch.matches?(high, eight_k([]))
    assert SecioEx.Watch.matches?(high, eight_k(["1.05"]))
    refute SecioEx.Watch.matches?(high, %{"formType" => "CORRESP"})
    assert SecioEx.Watch.matches?([name: :any, min: :low], %{"formType" => "CORRESP"})
  end

  test "form and ticker rules use the stream filter" do
    rule = [name: :insiders, form_types: "4", tickers: "aapl"]
    form4 = %{"formType" => "4", "ticker" => "AAPL"}

    assert SecioEx.Watch.matches?(rule, form4)
    assert SecioEx.Watch.matches?(rule, Map.put(form4, "formType", "4/A"))
    refute SecioEx.Watch.matches?(rule, %{"formType" => "4", "ticker" => "MSFT"})
    refute SecioEx.Watch.matches?(rule, %{"formType" => "424B4", "ticker" => "AAPL"})
    refute SecioEx.Watch.matches?(rule, eight_k(["1.05"]) |> Map.put("ticker", "AAPL"))
  end

  test "a rule needs a name, a known floor, and a real item" do
    assert_raise ArgumentError, ~r/name/, fn ->
      SecioEx.Watch.matches?([items: ["1.05"]], eight_k(["1.05"]))
    end

    assert_raise ArgumentError, ~r/min/, fn ->
      SecioEx.Watch.matches?([name: :x, min: :urgent], eight_k([]))
    end

    assert_raise ArgumentError, ~r/1\.05/, fn ->
      SecioEx.Watch.matches?([name: :x, items: ["bankruptcy"]], eight_k([]))
    end
  end

  test "one socket feeds every rule" do
    parent = self()

    connect = fn opts ->
      send(parent, {:socket, opts})
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end

    on = fn filing -> send(parent, {:on, filing["accessionNo"]}) end

    assert {:ok, watch} =
             SecioEx.Watch.start_link(
               api_key: @key,
               subscriber: parent,
               connect: connect,
               rules: [
                 [name: :cyber, items: ["1.05"]],
                 [name: :insiders, form_types: ["4"], tickers: ["AAPL"], on: on]
               ]
             )

    assert_received {:socket, opts}
    assert opts[:subscriber] == watch
    assert opts[:api_key] == @key
    refute Keyword.has_key?(opts, :form_types)

    cyber = eight_k(["1.05"]) |> Map.put("accessionNo", "cyber-1")
    insider = %{"formType" => "4", "ticker" => "AAPL", "accessionNo" => "form-4"}
    other = %{"formType" => "10-Q", "ticker" => "AAPL", "accessionNo" => "quiet"}

    send(watch, {:secio_ex, :connected})
    send(watch, {:secio_ex, {:filings, [cyber, insider, other]}})

    assert_receive {:secio_ex, :connected}
    assert_receive {:secio_ex, {:alert, :cyber, ^cyber}}
    assert_receive {:on, "form-4"}
    refute_receive {:secio_ex, {:alert, :insiders, _}}
    refute_receive {:on, "cyber-1"}
    refute_receive {:on, "quiet"}

    assert Process.alive?(watch)
    assert :ok = SecioEx.Watch.stop(watch)
    refute Process.alive?(watch)
  end

  test "a raising callback is reported and leaves the watcher up" do
    parent = self()
    connect = fn _opts -> {:ok, spawn(fn -> Process.sleep(:infinity) end)} end

    {:ok, watch} =
      SecioEx.Watch.start_link(
        api_key: @key,
        subscriber: parent,
        connect: connect,
        rules: [[name: :cyber, items: ["1.05"], on: fn _filing -> raise "boom apiKey=secret" end]]
      )

    send(watch, {:secio_ex, {:filings, [eight_k(["1.05"])]}})

    assert_receive {:secio_ex, {:callback_error, :cyber, message}}
    assert message =~ "boom"
    refute message =~ "secret"
    assert Process.alive?(watch)
    SecioEx.Watch.stop(watch)
  end

  test "refuses to open a socket without a way to deliver a match" do
    connect = fn _opts -> flunk("opened a socket") end

    assert_raise ArgumentError, ~r/subscriber/, fn ->
      SecioEx.Watch.start_link(
        api_key: @key,
        connect: connect,
        rules: [[name: :cyber, items: ["1.05"]]]
      )
    end

    assert_raise ArgumentError, ~r/at least one/, fn ->
      SecioEx.Watch.start_link(api_key: @key, connect: connect, rules: [])
    end

    assert {:error, :down} =
             SecioEx.Watch.start_link(
               api_key: @key,
               connect: fn _opts -> {:error, :down} end,
               rules: [[name: :cyber, items: ["1.05"], on: fn _filing -> :ok end]]
             )
  end

  defp eight_k(items) do
    %{"formType" => "8-K", "items" => items, "ticker" => "AAPL"}
  end
end
