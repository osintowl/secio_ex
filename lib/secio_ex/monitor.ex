defmodule SecioEx.Monitor do
  @moduledoc """
  Live terminal for the SEC filing stream.

  `mix secio.monitor` is the usual entry. `run/1` blocks until quit.

  8-K item 1.05 (material cybersecurity incident) is drawn in red and badged
  `CYBER`, same as bankruptcy, restatement, delisting, and change-in-control.
  """

  alias SecioEx.Monitor.Screen

  @bell_gap_ms 2_000

  def run(opts \\ []) do
    mode = resolve_mode(opts)
    parent = self()
    watch = SecioEx.Watchlist.new(opts[:watch])
    filter_opts = [form_types: opts[:form_types], tickers: opts[:tickers], ciks: opts[:ciks]]
    filtered = SecioEx.StreamFilter.active?(SecioEx.StreamFilter.new(filter_opts))

    if mode == :dashboard, do: enter_ui()
    System.at_exit(fn _ -> restore_ui() end)

    api_key = SecioEx.ApiKey.resolve!(opts)

    case SecioEx.StreamApi.start_link(
           api_key: api_key,
           subscriber: parent,
           form_types: opts[:form_types],
           tickers: opts[:tickers],
           ciks: opts[:ciks]
         ) do
      {:ok, stream} ->
        input = if mode == :dashboard and stdin_tty?(), do: start_input(parent)
        if seconds = opts[:seconds], do: Process.send_after(parent, :quit, seconds * 1_000)
        if mode == :dashboard, do: Process.send_after(parent, :tick, 1_000)

        state =
          initial_state(mode, watch, filtered)
          |> Map.put(:alerts_only, opts[:alerts_only] == true)
          |> Map.put(:bell, Keyword.get(opts, :bell, mode != :json))
          |> draw()

        try do
          loop(state)
        after
          SecioEx.StreamApi.stop(stream)
          if input, do: Process.exit(input, :kill)
          restore_ui()
        end

      {:error, reason} ->
        restore_ui()
        raise "SEC stream failed to start: #{scrub(reason)}"
    end
  end

  defp loop(state) do
    receive do
      {:secio_ex, message} ->
        state |> on_stream(message) |> loop()

      {:key, key} ->
        state |> on_key(key) |> draw() |> loop()

      :tick ->
        Process.send_after(self(), :tick, 1_000)
        state |> draw() |> loop()

      :quit ->
        :ok
    end
  end

  defp on_stream(state, :connected) do
    note(state, "connected")
    %{state | status: :live, reason: nil} |> draw()
  end

  defp on_stream(state, {:disconnected, reason}) do
    note(state, "reconnecting: " <> reason)

    %{state | status: :reconnecting, reason: reason, reconnects: state.reconnects + 1}
    |> draw()
  end

  defp on_stream(state, {:filings, filings}) do
    state = alert(state, filings)
    emit(state, filings)

    state
    |> store(filings)
    |> draw()
  end

  defp on_stream(state, :bad_frame) do
    %{state | note: "Ignored a malformed frame"} |> draw()
  end

  defp on_stream(state, {:callback_error, message}) do
    %{state | note: "Callback error: " <> message} |> draw()
  end

  defp on_stream(state, _), do: state

  defp on_key(state, :quit) do
    send(self(), :quit)
    state
  end

  defp on_key(state, :alerts) do
    %{state | alerts_only: not state.alerts_only, scroll: 0}
  end

  defp on_key(state, :pause) do
    if state.paused do
      %{state | paused: false, frozen: nil, scroll: 0}
    else
      %{state | paused: true, frozen: state.recent}
    end
  end

  defp on_key(state, :watch) do
    if SecioEx.Watchlist.empty?(state.watch) do
      %{state | note: "No watchlist. Start with --watch AAPL,MSFT"}
    else
      %{state | watch_only: not state.watch_only, scroll: 0, note: nil}
    end
  end

  defp on_key(state, :older) do
    %{state | scroll: min(state.scroll + 1, max_scroll(state))}
  end

  defp on_key(state, :newer) do
    %{state | scroll: max(state.scroll - 1, 0)}
  end

  defp on_key(state, :reset), do: %{state | scroll: 0}
  defp on_key(state, _), do: state

  defp store(state, filings) do
    critical = Enum.count(filings, &(SecioEx.FilingView.signal(&1) == :critical))

    by_form =
      Enum.reduce(filings, state.by_form, fn filing, acc ->
        form = SecioEx.FilingView.form_type(filing)
        Map.update(acc, form, 1, &(&1 + 1))
      end)

    recent =
      if state.mode == :dashboard do
        filings
        |> Enum.map(&SecioEx.FilingView.slim/1)
        |> Kernel.++(state.recent)
        |> Enum.take(500)
      else
        state.recent
      end

    %{
      state
      | seen: state.seen + length(filings),
        critical: state.critical + critical,
        by_form: by_form,
        recent: recent
    }
  end

  defp alert(%{bell: true, paused: false} = state, filings) do
    now = System.monotonic_time(:millisecond)

    if now - state.last_bell > @bell_gap_ms and Enum.any?(filings, &alert?(state, &1)) do
      IO.write("\a")
      %{state | last_bell: now}
    else
      state
    end
  end

  defp alert(state, _filings), do: state

  defp alert?(state, filing) do
    SecioEx.FilingView.signal(filing) == :critical or
      SecioEx.Watchlist.hit?(filing, state.watch)
  end

  defp note(%{mode: :dashboard}, _), do: :ok
  defp note(_state, text), do: IO.puts(:stderr, text)

  defp emit(%{mode: :plain}, filings) do
    Enum.each(filings, &IO.puts(SecioEx.FilingView.plain(&1)))
  end

  defp emit(%{mode: :json}, filings) do
    Enum.each(filings, &IO.puts(Jason.encode!(&1)))
  end

  defp emit(_, _), do: :ok

  defp draw(%{mode: :dashboard} = state) do
    state = with_clock(state)

    frame =
      state
      |> Screen.lines()
      |> Enum.map_join("\n", &(&1 <> "\e[K"))

    IO.write("\e[H" <> frame <> "\e[J")
    state
  end

  defp draw(state), do: state

  defp max_scroll(state) do
    rows = max(state.rows, 8)
    body = rows - 6
    slots = if body < 4, do: max(body, 1), else: div(body, 2)
    shown = length(Enum.filter(display_recent(state), &shown?(&1, state)))
    max(shown - slots, 0)
  end

  defp display_recent(%{paused: true, frozen: frozen}) when is_list(frozen), do: frozen
  defp display_recent(state), do: state.recent

  defp shown?(filing, state) do
    alerts_ok = not state.alerts_only or SecioEx.FilingView.signal(filing) in [:critical, :high]
    watch_ok = not state.watch_only or SecioEx.Watchlist.hit?(filing, state.watch)
    alerts_ok and watch_ok
  end

  defp with_clock(state) do
    {cols, rows} = terminal_size()
    now = System.monotonic_time(:second)

    %{
      state
      | cols: cols,
        rows: rows,
        uptime_s: max(now - state.started_mono, 0)
    }
  end

  defp terminal_size do
    {io_dim(:columns, 100), io_dim(:rows, 32)}
  end

  defp io_dim(fun, default) do
    if function_exported?(:io, fun, 0) do
      case apply(:io, fun, []) do
        {:ok, n} when is_integer(n) and n > 0 -> n
        _ -> default
      end
    else
      default
    end
  end

  defp initial_state(mode, watch, filtered) do
    %{
      mode: mode,
      status: :connecting,
      started_mono: System.monotonic_time(:second),
      uptime_s: 0,
      seen: 0,
      critical: 0,
      reconnects: 0,
      by_form: %{},
      recent: [],
      scroll: 0,
      paused: false,
      frozen: nil,
      alerts_only: false,
      watch_only: false,
      watch: watch,
      watch_label: SecioEx.Watchlist.label(watch),
      filtered: filtered,
      cols: 100,
      rows: 32,
      note: nil,
      reason: nil,
      bell: true,
      last_bell: 0,
      pending: []
    }
  end

  defp resolve_mode(opts) do
    cond do
      opts[:mode] == :json -> :json
      opts[:mode] == :plain -> :plain
      opts[:mode] == :dashboard -> :dashboard
      tty?() -> :dashboard
      true -> :plain
    end
  end

  defp tty?, do: match?({:ok, _}, :io.columns())

  defp stdin_tty?, do: match?({_, 0}, System.cmd("sh", ["-c", "test -t 0"]))

  defp start_input(parent) do
    spawn(fn -> input_loop(parent) end)
  end

  defp input_loop(parent) do
    case IO.getn("", 1) do
      :eof ->
        send(parent, :quit)

      "q" ->
        send(parent, {:key, :quit})

      "Q" ->
        send(parent, {:key, :quit})

      "a" ->
        send(parent, {:key, :alerts})
        input_loop(parent)

      "A" ->
        send(parent, {:key, :alerts})
        input_loop(parent)

      "p" ->
        send(parent, {:key, :pause})
        input_loop(parent)

      "w" ->
        send(parent, {:key, :watch})
        input_loop(parent)

      "W" ->
        send(parent, {:key, :watch})
        input_loop(parent)

      "r" ->
        send(parent, {:key, :reset})
        input_loop(parent)

      "j" ->
        send(parent, {:key, :older})
        input_loop(parent)

      "k" ->
        send(parent, {:key, :newer})
        input_loop(parent)

      "\e" ->
        case IO.getn("", 2) do
          "[A" -> send(parent, {:key, :newer})
          "[B" -> send(parent, {:key, :older})
          _ -> :ok
        end

        input_loop(parent)

      _ ->
        input_loop(parent)
    end
  end

  defp enter_ui do
    {saved, status} = System.cmd("stty", ["-g"], stderr_to_stdout: true)

    if status == 0 do
      :persistent_term.put({__MODULE__, :stty}, String.trim(saved))
      System.cmd("stty", ["-echo", "-icanon", "min", "1", "time", "0"])
      IO.write("\e[?1049h\e[?25l")
    end
  end

  defp restore_ui do
    case :persistent_term.get({__MODULE__, :stty}, nil) do
      nil ->
        :ok

      saved ->
        :persistent_term.erase({__MODULE__, :stty})
        IO.write("\e[?25h\e[?1049l")
        System.cmd("stty", [saved], stderr_to_stdout: true)
    end
  end

  defp scrub(reason) do
    reason
    |> inspect(limit: 8, printable_limit: 80)
    |> String.replace(~r/apiKey=[^&\s"\\]+/, "apiKey=[redacted]")
  end
end
