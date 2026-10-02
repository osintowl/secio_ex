defmodule SecioEx.Watch do
  @moduledoc """
  One live filing socket, many alert rules.

  `mix secio.monitor` is the terminal. `Watch` is the process other
  applications start. It opens a single `SecioEx.StreamApi` connection and
  runs every rule against each filing. The stream does not replay filings
  from before the socket connected.

  A rule matches with the same form, ticker, and CIK behaviour as
  `SecioEx.StreamFilter`. `:items` matches 8-K item numbers such as `"1.05"`,
  and only on `8-K` or `8-K/A`. Several items match if any one of them is
  present. `:min` is a floor on `SecioEx.FilingView.signal/1`.

  `:on` is called with one filing, in its own process. A rule without `:on`
  sends `{:secio_ex, {:alert, name, filing}}` to `:subscriber`. Connection
  messages (`:connected`, `{:disconnected, reason}`) go to that subscriber too.

  ## Examples

      children = [
        {SecioEx.Watch,
         rules: [
           [name: :cyber, items: ["1.05"], on: &MyApp.Alerts.cyber/1],
           [name: :restatement, items: ["4.02"], min: :critical, on: &MyApp.Alerts.restatement/1],
           [name: :insiders, form_types: ["4"], tickers: ["AAPL"], on: &MyApp.Alerts.form4/1]
         ]}
      ]

      {:ok, watch} =
        SecioEx.Watch.start_link(
          subscriber: self(),
          rules: [[name: :cyber, items: ["1.05"]]]
        )

      receive do
        {:secio_ex, {:alert, :cyber, filing}} -> filing
      end

      SecioEx.Watch.stop(watch)
  """

  use GenServer

  alias SecioEx.FilingView
  alias SecioEx.StreamFilter

  @rule_keys [:name, :form_types, :tickers, :ciks, :items, :min, :on]
  @levels [:low, :normal, :high, :critical]
  @rank Map.new(Enum.with_index(@levels))

  @doc """
  Starts a watcher.

  Options:

    * `:rules` — required. A list of rule maps or keyword lists. One bare
      rule keyword is accepted too.
    * `:subscriber` — pid for rules that have no `:on`, and for connection
      messages
    * `:api_key` or `:api_key_file` — see `SecioEx.ApiKey`
    * `:name` — registered process name
  """
  def start_link(opts \\ []) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    rules = compile_all(Keyword.get(opts, :rules))
    subscriber = opts[:subscriber]

    if is_nil(subscriber) and Enum.any?(rules, &is_nil(&1.on)) do
      raise ArgumentError, "pass :subscriber or an :on function for each rule"
    end

    # The socket has to start from the watcher process so it can subscribe to
    # itself. A failed connect stops that process with :normal; the reason is
    # reported on this ref so the caller is not killed by the link.
    ref = make_ref()

    case GenServer.start_link(__MODULE__, {opts, rules, self(), ref}, gen_opts) do
      {:ok, pid} ->
        receive do
          {^ref, :ok} -> {:ok, pid}
        after
          0 -> {:ok, pid}
        end

      {:error, :normal} ->
        receive do
          {^ref, {:error, reason}} -> {:error, reason}
        after
          0 -> {:error, :normal}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Closes the socket and stops the watcher."
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid)
  catch
    :exit, _reason -> :ok
  end

  @doc """
  Returns true when the rule matches the filing.

  Accepts a rule map or keyword. This does not open a socket.
  """
  def matches?(rule, filing) when is_map(filing) do
    match_rule?(compile_rule(rule), filing)
  end

  @impl true
  def init({opts, rules, parent, ref}) do
    subscriber = opts[:subscriber]
    connect = Keyword.get(opts, :connect, &SecioEx.StreamApi.start_link/1)

    stream_opts =
      opts
      |> Keyword.take([:api_key, :api_key_file])
      |> Keyword.put(:subscriber, self())

    case connect.(stream_opts) do
      {:ok, stream} ->
        send(parent, {ref, :ok})
        {:ok, %{rules: rules, stream: stream, subscriber: subscriber}}

      {:error, reason} ->
        send(parent, {ref, {:error, reason}})
        {:stop, :normal}
    end
  end

  @impl true
  def terminate(_reason, %{stream: stream}) when is_pid(stream) do
    SecioEx.StreamApi.stop(stream)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  @impl true
  def handle_info({:secio_ex, {:filings, filings}}, state) when is_list(filings) do
    Enum.each(filings, &deliver(&1, state))
    {:noreply, state}
  end

  def handle_info({:secio_ex, message}, %{subscriber: subscriber} = state) do
    notify(subscriber, message)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp deliver(filing, state) do
    Enum.each(state.rules, fn rule ->
      if match_rule?(rule, filing), do: fire(rule, filing, state.subscriber)
    end)
  end

  defp fire(%{on: nil, name: name}, filing, subscriber) do
    notify(subscriber, {:alert, name, filing})
  end

  defp fire(%{on: callback, name: name}, filing, subscriber) when is_function(callback, 1) do
    Task.start(fn -> invoke(callback, name, filing, subscriber) end)
    :ok
  end

  defp invoke(callback, name, filing, subscriber) do
    try do
      callback.(filing)
    rescue
      error ->
        notify(subscriber, {:callback_error, name, scrub(Exception.message(error))})
    catch
      kind, reason ->
        notify(
          subscriber,
          {:callback_error, name, scrub("#{kind}: #{inspect(reason, limit: 5)}")}
        )
    end
  end

  defp notify(subscriber, message) when is_pid(subscriber) do
    send(subscriber, {:secio_ex, message})
  end

  defp notify(_subscriber, _message), do: :ok

  defp match_rule?(rule, filing) do
    StreamFilter.match?(filing, rule.filter) and items_ok?(filing, rule.items) and
      severity_ok?(filing, rule.min)
  end

  defp items_ok?(_filing, []), do: true

  defp items_ok?(filing, items) do
    FilingView.form_type(filing) in ["8-K", "8-K/A"] and
      Enum.any?(items, &(&1 in FilingView.item_numbers(filing)))
  end

  defp severity_ok?(_filing, nil), do: true

  defp severity_ok?(filing, min) do
    Map.fetch!(@rank, FilingView.signal(filing)) >= Map.fetch!(@rank, min)
  end

  defp compile_all(rules) when is_map(rules) and not is_struct(rules), do: [compile_rule(rules)]

  defp compile_all(rules) when is_list(rules) do
    cond do
      rules == [] ->
        raise ArgumentError, "pass at least one rule"

      Keyword.keyword?(rules) and Enum.all?(rules, fn {key, _} -> key in @rule_keys end) ->
        [compile_rule(rules)]

      true ->
        Enum.map(rules, &compile_rule/1)
    end
  end

  defp compile_all(_rules), do: raise(ArgumentError, "pass at least one rule")

  defp compile_rule(rule) when is_list(rule) or is_map(rule) do
    rule = Map.new(rule)
    unknown = Map.keys(rule) -- @rule_keys

    if unknown != [] do
      raise ArgumentError, "unknown rule option #{inspect(hd(unknown))}"
    end

    name = rule_name(Map.get(rule, :name))
    on = Map.get(rule, :on)
    min = Map.get(rule, :min)

    if not is_nil(on) and not is_function(on, 1) do
      raise ArgumentError, "rule #{inspect(name)} :on must take one argument"
    end

    if not is_nil(min) and min not in @levels do
      raise ArgumentError, "min must be :low, :normal, :high, or :critical"
    end

    %{
      name: name,
      filter:
        StreamFilter.new(
          form_types: Map.get(rule, :form_types, []),
          tickers: Map.get(rule, :tickers, []),
          ciks: Map.get(rule, :ciks, [])
        ),
      items: normalize_items(Map.get(rule, :items, [])),
      min: min,
      on: on
    }
  end

  defp compile_rule(_rule), do: raise(ArgumentError, "a rule must be a map or keyword list")

  defp rule_name(name) when is_atom(name) and not is_nil(name), do: name

  defp rule_name(name) when is_binary(name) do
    if String.trim(name) == "" do
      raise ArgumentError, "rule needs a :name"
    else
      name
    end
  end

  defp rule_name(_name), do: raise(ArgumentError, "rule needs a :name")

  defp normalize_items(nil), do: []

  defp normalize_items(items) do
    items
    |> List.wrap()
    |> Enum.flat_map(fn
      item when is_binary(item) ->
        item
        |> String.split(~r/\s*,\s*/, trim: true)
        |> Enum.map(&normalize_item/1)

      item ->
        [normalize_item(item)]
    end)
    |> Enum.uniq()
  end

  defp normalize_item(item) do
    number =
      item
      |> to_string()
      |> String.trim()
      |> String.replace(~r/^item\s*/i, "")
      |> String.replace("_", ".")
      |> String.replace("-", ".")
      |> String.trim()

    unless String.match?(number, ~r/^\d+\.\d+$/) do
      raise ArgumentError, "item must look like 1.05"
    end

    number
  end

  defp scrub(message) do
    message
    |> to_string()
    |> String.replace(~r/apiKey=[^&\s"\\]+/, "apiKey=[redacted]")
    |> String.slice(0, 200)
  end
end
