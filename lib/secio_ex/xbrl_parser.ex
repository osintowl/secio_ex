defmodule SecioEx.XbrlParser do
  @moduledoc """
  Read JSON produced by `SecioEx.XbrlToJson`.

  This module does not call the network. The converter normalizes statement
  names, so the same keys work across filers:

    * `CoverPage`
    * `StatementsOfIncome`
    * `StatementsOfComprehensiveIncome`
    * `BalanceSheets`
    * `StatementsOfCashFlows`
    * `StatementsOfShareholdersEquity`

  Each concept is a list of facts. `facts/1` flattens a statement into maps
  with `:concept`, `:value`, `:period`, `:unit`, and `:decimals`.
  """

  @roots [
    "CoverPage",
    "StatementsOfIncome",
    "StatementsOfComprehensiveIncome",
    "BalanceSheets",
    "StatementsOfCashFlows",
    "StatementsOfShareholdersEquity"
  ]

  @doc "The canonical statements that are present in `json`."
  def statements(json) when is_map(json) do
    for name <- @roots, section(json, name) != nil, into: %{} do
      {name, section(json, name)}
    end
  end

  @doc "Cover page facts, or nil when the filing has none."
  def cover_page(json), do: section(json, "CoverPage")

  @doc "Income statement, or nil."
  def income(json), do: section(json, "StatementsOfIncome")

  @doc "Balance sheet, or nil."
  def balance_sheet(json), do: section(json, "BalanceSheets")

  @doc "Cash flow statement, or nil."
  def cash_flows(json), do: section(json, "StatementsOfCashFlows")

  @doc "One statement object by its canonical name, or nil."
  def section(json, name) when is_map(json) and is_binary(name) do
    case Map.fetch(json, name) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  @doc """
  Flatten a statement into fact maps.

  A concept whose value is a list becomes one fact per entry. A single fact
  object, or a plain value on the cover page, becomes one fact.
  """
  def facts(statement) when is_map(statement) do
    Enum.flat_map(statement, fn {concept, values} ->
      concept = to_string(concept)

      values
      |> List.wrap()
      |> Enum.map(&fact(concept, &1))
    end)
  end

  def facts(_statement), do: []

  @doc "Facts for one concept name."
  def concept(statement, name) when is_binary(name) do
    statement
    |> facts()
    |> Enum.filter(&(&1.concept == name))
  end

  defp fact(concept, value) when is_map(value) do
    %{
      concept: concept,
      value: map_get(value, "value"),
      period: map_get(value, "period"),
      unit: map_get(value, "unitRef") || map_get(value, "unit"),
      decimals: map_get(value, "decimals")
    }
  end

  defp fact(concept, value) do
    %{concept: concept, value: value, period: nil, unit: nil, decimals: nil}
  end

  defp map_get(map, key) do
    Map.get(map, key) || Map.get(map, existing_atom(key))
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end
end
