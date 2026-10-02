defmodule SecioEx.StreamApi do
  @moduledoc """
  WebSocket client for the sec-api.io real-time filing stream.

  Endpoint: `wss://stream.sec-api.io?apiKey=YOUR_API_KEY`

  Each text frame is a JSON array of filing metadata. The server sends a
  protocol ping about every 25 seconds. WebSockex answers those pings.
  Dropped connections reconnect with exponential backoff.

  The live terminal is `mix secio.monitor`. `SecioEx.Watch` runs named rules
  on one connection.

  A `:callback` runs in its own process. A slow callback cannot delay the
  pong that keeps the socket open. Subscriber messages are sent from the
  socket process.
  """

  use WebSockex

  @url "wss://stream.sec-api.io"
  @min_backoff 1_000
  @max_backoff 30_000

  @doc """
  Opens the stream.

  Options:

    * `:api_key` or `:api_key_file` — see `SecioEx.ApiKey`
    * `:subscriber` — pid that receives `{:secio_ex, message}`
    * `:callback` — function invoked with each list of matched filings
    * `:form_types`, `:tickers`, `:ciks` — client-side filter
    * `:name` — registered process name

  Messages sent to the subscriber:

    * `:connected`
    * `{:disconnected, reason}`
    * `{:filings, filings}`
    * `:bad_frame`
  """
  def start_link(opts \\ []) do
    api_key = opts[:api_key] || SecioEx.ApiKey.resolve!(opts)

    state = %{
      callback: opts[:callback],
      subscriber: opts[:subscriber],
      filter: SecioEx.StreamFilter.new(opts),
      backoff: @min_backoff,
      stop: false,
      warned_bad_frame: false
    }

    url = @url <> "?" <> URI.encode_query(%{"apiKey" => api_key})

    socket_opts = [
      async: Keyword.get(opts, :async, true),
      handle_initial_conn_failure: true
    ]

    socket_opts =
      case opts[:name] do
        nil -> socket_opts
        name -> Keyword.put(socket_opts, :name, name)
      end

    WebSockex.start_link(url, __MODULE__, state, socket_opts)
  end

  @doc """
  Connects and calls `callback` with each batch of filings.

  Blocks until the first connection succeeds. The callback receives a list.
  """
  def sec_stream(api_key, callback \\ &default_callback/1) do
    start_link(api_key: api_key, callback: callback, async: false)
  end

  @doc """
  Closes the socket and stops reconnecting.
  """
  def stop(client) do
    WebSockex.cast(client, :stop)
  catch
    :exit, _ -> :ok
  end

  def handle_connect(_conn, state) do
    notify(state, :connected)
    {:ok, %{state | backoff: @min_backoff}}
  end

  def handle_frame({kind, msg}, state) when kind in [:text, :binary] do
    deliver_frame(msg, state)
  end

  def handle_frame(_frame, state), do: {:ok, state}

  def handle_cast(:stop, state) do
    {:close, %{state | stop: true}}
  end

  def handle_disconnect(_status, %{stop: true} = state), do: {:ok, state}

  def handle_disconnect(status, state) do
    notify(state, {:disconnected, scrub(status.reason)})

    case wait_backoff(state.backoff) do
      :stop ->
        {:ok, %{state | stop: true}}

      :continue ->
        {:reconnect, %{state | backoff: next_backoff(state.backoff)}}
    end
  end

  defp deliver_frame(msg, state) do
    case Jason.decode(msg) do
      {:ok, filings} when is_list(filings) ->
        deliver(filings, state)

      {:ok, %{} = filing} ->
        deliver([filing], state)

      {:ok, _} ->
        {:ok, state}

      {:error, _} ->
        state =
          if state.subscriber && not state.warned_bad_frame do
            notify(state, :bad_frame)
            %{state | warned_bad_frame: true}
          else
            state
          end

        {:ok, state}
    end
  end

  defp deliver(filings, state) do
    matched = Enum.filter(filings, &SecioEx.StreamFilter.match?(&1, state.filter))

    if matched != [] do
      notify(state, {:filings, matched})
      safe_callback(state, matched)
    end

    {:ok, state}
  end

  defp safe_callback(%{callback: callback} = state, filings) when is_function(callback, 1) do
    Task.start(fn ->
      try do
        callback.(filings)
      rescue
        error ->
          notify(state, {:callback_error, Exception.message(error)})
      catch
        kind, reason ->
          notify(state, {:callback_error, "#{kind}: #{inspect(reason)}"})
      end
    end)

    :ok
  end

  defp safe_callback(_, _), do: :ok

  defp notify(%{subscriber: pid}, message) when is_pid(pid), do: send(pid, {:secio_ex, message})
  defp notify(_, _), do: :ok

  defp next_backoff(current), do: min(current * 2, @max_backoff)

  defp wait_backoff(milliseconds) do
    deadline = System.monotonic_time(:millisecond) + milliseconds
    wait_until(deadline)
  end

  defp wait_until(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      :continue
    else
      receive do
        {:"$websockex_cast", :stop} -> :stop
      after
        min(remaining, 200) -> wait_until(deadline)
      end
    end
  end

  defp scrub(reason) do
    reason
    |> inspect(limit: 8, printable_limit: 80)
    |> String.replace(~r/apiKey=[^&\s"\\]+/, "apiKey=[redacted]")
    |> String.slice(0, 160)
  end

  defp default_callback(filings) do
    Enum.each(filings, &IO.puts(SecioEx.FilingView.plain(&1)))
  end
end
