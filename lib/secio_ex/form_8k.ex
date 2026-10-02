defmodule SecioEx.Form8K do
  require SecioEx.Search

  @moduledoc """
  Structured 8-K search.

  `POST https://api.sec-api.io/form-8k`

  This is not `SecioEx.ExtractorApi`. ExtractorApi returns the text of one
  item from a filing URL. This dataset parses some items into objects:
  `item4_01` (auditor changes), `item4_02` (restatements), and `item5_02`
  (directors and officers). Query a parsed object with `item4_02:*`.

  Every record also has an `items` array of headings, for example
  `"Item 4.02: Non-Reliance on Previously Issued Financial Statements..."`.
  `search_item("1.05")` matches that array. Item 1.05 has no parsed object
  here. The filing search finds every cybersecurity 8-K:

      SecioEx.QueryApi.search("formType:\\"8-K\\" AND items:\\"1.05\\"")
  """

  @doc """
  Search structured 8-K filings.

  ## Examples

      SecioEx.Form8K.search("item4_02:*", api_key: "your_api_key")
      SecioEx.Form8K.search_item("1.05", api_key: "your_api_key")
  """
  def search(query, opts \\ []) when is_binary(query) do
    SecioEx.Client.dataset("/form-8k", query, opts,
      size: 50,
      sort: SecioEx.Client.filed_at_desc()
    )
  end

  @doc "8-K filings for a ticker."
  def by_ticker(ticker, opts \\ []) when is_binary(ticker) do
    search("ticker:#{String.upcase(String.trim(ticker))}", opts)
  end

  @doc "8-K filings for a CIK. Leading zeros are not added."
  def by_cik(cik, opts \\ []) do
    search("cik:#{cik}", opts)
  end

  @doc """
  Filings whose `items` heading list includes this item.

  `search_item("1.05", opts)` queries `items:"Item 1.05"`.
  `search_item("4.02", opts)` queries `items:"Item 4.02"`.
  """
  def search_item(item, opts \\ []) do
    search(SecioEx.Client.phrase("items", item_label(item)), opts)
  end

  @doc """
  Heading stored in the `items` array, without the text after the number.

  `"4.02"`, `"item4_02"`, and `"Item 4.02"` all become `"Item 4.02"`.
  """
  def item_label(item) do
    number =
      item
      |> to_string()
      |> String.trim()
      |> String.replace(~r/^item\s*/i, "")
      |> String.replace("_", ".")
      |> String.replace("-", ".")
      |> String.trim()

    if number == "" or not String.match?(number, ~r/^\d/) do
      raise ArgumentError, "item is empty"
    end

    "Item " <> number
  end

  @doc """
  Map an item number to a parsed-object field.

  `"4.02"` and `"item4_02"` both become `"item4_02"`. The dataset parses
  `item4_01`, `item4_02`, and `item5_02`. Other numbers still convert, and
  the field is absent on the record.
  """
  def item_field(item) do
    normalized = item |> to_string() |> String.trim() |> String.downcase()

    normalized =
      cond do
        String.starts_with?(normalized, "item ") ->
          String.trim_leading(normalized, "item ")

        String.starts_with?(normalized, "item") ->
          String.trim_leading(normalized, "item")

        true ->
          normalized
      end

    suffix =
      normalized
      |> String.trim()
      |> String.replace(~r/[^0-9a-z]+/, "_")
      |> String.trim("_")

    if suffix == "" do
      raise ArgumentError, "item is empty"
    end

    "item" <> suffix
  end

  SecioEx.Search.pages()
end
