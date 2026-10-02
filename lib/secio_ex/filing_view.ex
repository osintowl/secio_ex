defmodule SecioEx.FilingView do
  @moduledoc """
  Display helpers for a filing from the SEC stream.

  Critical 8-K items:

    * `1.03` — bankruptcy or receivership
    * `1.05` — material cybersecurity incident
    * `3.01` — delisting or failure to satisfy a listing rule
    * `4.02` — non-reliance on previously issued financial statements
    * `5.01` — changes in control

  Late notices (`NT 10-K`, `NT 10-Q`, `NT 20-F`) and Form 25 delistings are
  critical too. `1.05` is critical only on `8-K` and `8-K/A`.
  """

  @critical_items ~w(1.03 1.05 3.01 4.02 5.01)
  @hot_items ~w(1.01 1.02 2.01 2.02 2.04 2.05 2.06 4.01 5.02 5.07)
  @high_forms [
    "8-K",
    "8-K/A",
    "4",
    "4/A",
    "3",
    "5",
    "SC 13D",
    "SC 13D/A",
    "S-1",
    "S-1/A",
    "EFFECT",
    "10-K",
    "10-K/A",
    "10-Q",
    "10-Q/A",
    "425"
  ]
  @low_forms ~w(CORRESP UPLOAD CERT)
  @late_forms [
    "NT 10-K",
    "NT 10-Q",
    "NT 10-K/A",
    "NT 10-Q/A",
    "NT 20-F",
    "NT 20-F/A",
    "25-NSE",
    "25-NSE/A"
  ]

  @kept ~w(
    formType ticker cik companyName companyNameLong filedAt description items
    linkToFilingDetails accessionNo entities seriesAndClassesContractsInformation
  )

  def signal(filing) do
    form = form_type(filing)
    numbers = item_numbers(filing)

    cond do
      form in @late_forms -> :critical
      eight_k?(form) and Enum.any?(numbers, &(&1 in @critical_items)) -> :critical
      eight_k?(form) and Enum.any?(numbers, &(&1 in @hot_items)) -> :high
      form in @high_forms -> :high
      form in @low_forms -> :low
      true -> :normal
    end
  end

  def badge(filing) do
    form = form_type(filing)
    numbers = item_numbers(filing)

    cond do
      eight_k?(form) and "1.05" in numbers -> "CYBER"
      eight_k?(form) and "1.03" in numbers -> "BK"
      eight_k?(form) and "4.02" in numbers -> "RESTATE"
      eight_k?(form) and "3.01" in numbers -> "DELIST"
      eight_k?(form) and "5.01" in numbers -> "CONTROL"
      form in @late_forms -> "LATE"
      eight_k?(form) and "2.02" in numbers -> "EARNINGS"
      eight_k?(form) and "4.01" in numbers -> "AUDITOR"
      eight_k?(form) and "5.02" in numbers -> "OFFICER"
      eight_k?(form) and "2.01" in numbers -> "DEAL"
      eight_k?(form) and "1.01" in numbers -> "AGREEMENT"
      form in ["4", "4/A"] -> "INSIDER"
      form in ["SC 13D", "SC 13D/A"] -> "13D"
      form in ["S-1", "S-1/A"] -> "IPO"
      form == "EFFECT" -> "EFFECT"
      true -> nil
    end
  end

  def level_label(:critical), do: "CRIT"
  def level_label(:high), do: "HIGH"
  def level_label(:low), do: "LOW"
  def level_label(_), do: ""

  def form_type(filing) do
    filing
    |> Map.get("formType", "")
    |> to_string()
    |> String.trim()
    |> String.upcase()
  end

  def ticker(%{"ticker" => ticker}) when is_binary(ticker) and ticker != "" do
    ticker |> String.trim() |> String.upcase()
  end

  def ticker(%{"cik" => cik}) when cik not in [nil, ""], do: "CIK" <> to_string(cik)
  def ticker(_), do: "-"

  def company_name(filing) do
    raw = filing["companyName"] || filing["companyNameLong"] || "Unknown"

    raw
    |> to_string()
    |> String.replace(~r/\s+\((Filer|Issuer|Reporting|Subject|Filed by)\)$/i, "")
    |> String.trim()
  end

  def clock(%{"filedAt" => ts}) when is_binary(ts) do
    # filedAt is already Eastern Time. DateTime.from_iso8601 shifts it to UTC,
    # which would show 20:06 for a 16:06 ET acceptance.
    case Regex.run(~r/(\d{2}:\d{2}:\d{2})/, ts) do
      [_, clock] -> clock
      _ -> "--:--:--"
    end
  end

  def clock(_), do: "--:--:--"

  def item_numbers(%{} = filing) do
    parts =
      [filing["description"] | List.wrap(filing["items"])]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&stringify/1)

    Regex.scan(~r/\b(\d+\.\d+)\b/, Enum.join(parts, " "))
    |> Enum.map(fn [_, number] -> number end)
    |> Enum.uniq()
  end

  def item_numbers(_), do: []

  def items_text(filing) do
    case filing["items"] do
      items when is_list(items) and items != [] ->
        items |> Enum.map(&stringify/1) |> Enum.join(" · ")

      _ ->
        filing["description"] |> to_string() |> String.trim()
    end
  end

  def short_link(url) when is_binary(url) and url != "" do
    url
    |> String.replace_prefix("https://", "")
    |> String.replace_prefix("http://", "")
    |> String.replace_prefix("www.", "")
  end

  def short_link(_), do: ""

  def plain(filing) do
    badge = badge(filing)
    badge = if badge, do: "  " <> badge, else: ""
    level = level_label(signal(filing)) |> String.pad_trailing(4)

    [
      clock(filing),
      level,
      String.pad_trailing(form_type(filing), 10),
      String.pad_trailing(ticker(filing), 6),
      company_name(filing) <> badge,
      items_text(filing),
      filing["linkToFilingDetails"] || ""
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("  ")
  end

  def slim(filing) when is_map(filing) do
    entities =
      filing
      |> Map.get("entities", [])
      |> List.wrap()
      |> Enum.map(fn
        %{} = entity -> Map.take(entity, ["cik", "companyName"])
        _ -> %{}
      end)

    filing
    |> Map.take(@kept)
    |> Map.put("entities", entities)
  end

  def headline(filing, cols) do
    badge = String.pad_trailing(badge(filing) || "", 9)
    level = String.pad_trailing(level_label(signal(filing)), 4)
    prefix = Enum.join([clock(filing), fit(form_type(filing), 10), fit(ticker(filing), 6)], " ")
    suffix = badge <> " " <> level
    company_width = max(cols - String.length(prefix) - String.length(suffix) - 2, 0)
    company = fit(company_name(filing), company_width)

    [prefix, company, suffix]
    |> Enum.join(" ")
    |> clip(cols)
  end

  def detail(filing, cols) do
    indent = min(28, max(cols - 24, 0))
    left = items_text(filing)
    link = short_link(filing["linkToFilingDetails"])
    room = cols - indent

    body =
      cond do
        room <= 0 ->
          ""

        link == "" ->
          clip(left, room)

        String.length(left) + String.length(link) + 2 <= room ->
          gap = room - String.length(left) - String.length(link)
          left <> String.duplicate(" ", gap) <> link

        true ->
          clip(left, room)
      end

    clip(String.duplicate(" ", indent) <> body, cols)
  end

  def style(filing, watch) do
    cond do
      signal(filing) == :critical -> :critical
      SecioEx.Watchlist.hit?(filing, watch) -> :watch
      true -> signal(filing)
    end
  end

  defp eight_k?(form), do: form in ["8-K", "8-K/A"]

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp fit(_text, width) when width <= 0, do: ""

  defp fit(text, width) do
    text = text |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim()

    cond do
      String.length(text) <= width -> String.pad_trailing(text, width)
      width == 1 -> "…"
      true -> String.slice(text, 0, width - 1) <> "…"
    end
  end

  defp clip(text, cols) do
    if String.length(text) > cols, do: String.slice(text, 0, cols), else: text
  end
end
