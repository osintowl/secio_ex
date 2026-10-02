defmodule SecioEx.Monitor.Screen do
  @moduledoc false

  def lines(state) do
    cols = max(state.cols, 20)
    rows = max(state.rows, 8)
    body_rows = rows - 6
    compact = body_rows < 4
    slots = if compact, do: max(body_rows, 1), else: div(body_rows, 2)

    body =
      case Enum.slice(source(state), state.scroll, slots) do
        [] ->
          message =
            if state.status == :live,
              do: "Waiting for filings…",
              else: "Connecting to the SEC stream…"

          pad([{:plain, message}], body_rows)

        filings ->
          filings
          |> filing_lines(cols, compact, state.watch)
          |> pad(body_rows)
      end

    ([
       title(state, cols),
       stats(state, cols),
       meta(state, cols),
       {:plain, rule(cols)}
     ] ++
       body ++
       [
         {:plain, rule(cols)},
         {:plain, clip("q quit   a alerts   p pause   w watch   j/k scroll   r live", cols)}
       ])
    |> Enum.take(rows)
    |> then(fn painted ->
      missing = rows - length(painted)
      if missing > 0, do: painted ++ List.duplicate({:plain, ""}, missing), else: painted
    end)
    |> Enum.map(&color_line/1)
  end

  defp source(%{paused: true, frozen: frozen} = state) when is_list(frozen) do
    Enum.filter(frozen, &visible?(&1, state))
  end

  defp source(state), do: Enum.filter(state.recent, &visible?(&1, state))

  defp visible?(filing, state) do
    alerts_ok = not state.alerts_only or SecioEx.FilingView.signal(filing) in [:critical, :high]
    watch_ok = not state.watch_only or SecioEx.Watchlist.hit?(filing, state.watch)
    alerts_ok and watch_ok
  end

  defp filing_lines(filings, cols, compact, watch) do
    Enum.flat_map(filings, fn filing ->
      style = SecioEx.FilingView.style(filing, watch)
      headline = {SecioEx.FilingView.headline(filing, cols), style}

      if compact do
        [headline]
      else
        [headline, {SecioEx.FilingView.detail(filing, cols), style}]
      end
    end)
  end

  defp title(state, cols) do
    status =
      case state.status do
        :live -> "LIVE"
        :reconnecting -> "RECONNECT"
        _ -> "CONNECTING"
      end

    left = " SEC FILINGS"
    right = status <> "  " <> format_duration(state.uptime_s) <> " "
    gap = max(cols - String.length(left) - String.length(right), 1)
    {:status, clip(left <> String.duplicate(" ", gap) <> right, cols), state.status}
  end

  defp stats(state, cols) do
    noun = if state.filtered, do: "matched", else: "seen"

    text =
      "#{state.seen} #{noun}   #{rate(state.seen, state.uptime_s)}/min   #{state.critical} critical   #{state.reconnects} reconnects   #{form_mix(state.by_form)}"

    {:plain, clip(text, cols)}
  end

  defp meta(state, cols) do
    flags =
      [
        if(state.paused, do: "PAUSED", else: "follow"),
        if(state.alerts_only, do: "alerts"),
        if(state.watch_only, do: "watch-only"),
        if(state.scroll > 0, do: "scroll #{state.scroll}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("  ")

    watch =
      case state.watch_label do
        label when is_binary(label) and label != "" -> "watch " <> label <> "   "
        _ -> ""
      end

    reason =
      if state.status == :reconnecting and is_binary(state.reason) and state.reason != "" do
        "   " <> state.reason
      else
        ""
      end

    note = if state.note in [nil, ""], do: "", else: "   " <> state.note
    {:plain, clip(watch <> flags <> reason <> note, cols)}
  end

  defp form_mix(by_form) do
    by_form
    |> Enum.sort_by(fn {form, count} -> {-count, form} end)
    |> Enum.take(5)
    |> Enum.map(fn {form, count} -> "#{form} #{count}" end)
    |> Enum.join("  ")
  end

  defp pad(lines, rows) do
    missing = rows - length(lines)

    if missing > 0 do
      lines ++ List.duplicate({:plain, ""}, missing)
    else
      Enum.take(lines, rows)
    end
  end

  defp color_line({:plain, ""}), do: ""
  defp color_line({:plain, text}), do: text

  defp color_line({:status, text, status}) do
    color =
      case status do
        :live -> IO.ANSI.green()
        :reconnecting -> IO.ANSI.yellow()
        _ -> IO.ANSI.cyan()
      end

    IO.ANSI.bright() <> color <> text <> IO.ANSI.reset()
  end

  defp color_line({text, style}) do
    color =
      case style do
        :critical -> IO.ANSI.red() <> IO.ANSI.bright()
        :watch -> IO.ANSI.magenta() <> IO.ANSI.bright()
        :high -> IO.ANSI.yellow()
        :low -> IO.ANSI.light_black()
        _ -> ""
      end

    if color == "", do: text, else: color <> text <> IO.ANSI.reset()
  end

  defp format_duration(seconds) when is_integer(seconds) and seconds > 0 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      :io_lib.format("~B:~2..0B:~2..0B", [hours, minutes, secs]) |> to_string()
    else
      :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> to_string()
    end
  end

  defp format_duration(_), do: "00:00"

  defp rate(seen, uptime_s) do
    per_min = seen * 60 / max(uptime_s, 1)
    :erlang.float_to_binary(per_min * 1.0, decimals: 1)
  end

  defp rule(cols), do: String.duplicate("─", cols)

  defp clip(text, cols) do
    if String.length(text) > cols, do: String.slice(text, 0, cols), else: text
  end
end
