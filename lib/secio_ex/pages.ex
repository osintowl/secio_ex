defmodule SecioEx.PageError do
  @moduledoc """
  Raised when `stream/2` cannot fetch a page.

  The message is only the HTTP status. The response body stays on `:reason`
  so a log of the exception does not include the API key.
  """

  defexception [:reason, :from, :page]

  @impl true
  def message(%{reason: %{status_code: status}}) when is_integer(status), do: "HTTP #{status}"
  def message(%{reason: status}) when is_integer(status), do: "HTTP #{status}"
  def message(_exception), do: "HTTP error"
end

defmodule SecioEx.Pages do
  @moduledoc """
  Walk sec-api.io search windows.

  A Lucene response holds at most 10,000 hits for one query. `stream/2` and
  `all/2` advance `:from` by the requested page size until a short page, an
  exact total, or offset 10,000. `:limit` caps how many records are returned,
  and it is also capped at 10,000.

  `:page_size` is only the "this page is full" threshold for full-text search.
  Rows are not cut to that size. `:limit` is what cuts a page short.

  Totals use `total.value` when `total.relation` is `"eq"` or missing. A
  `"gte"` total does not end the walk; the 10,000 offset does. The record
  list is `filings`, `data`, or the body when the body is a list. A bare list
  is one page.

  `all/2` returns `{:ok, records}`. If a later page fails, the error keeps the
  records already fetched. The first page's error is returned unchanged.
  `stream/2` raises `SecioEx.PageError`.

  One window cannot pass 10,000 hits. Split a date range with `date_windows/3`,
  `all_between/3`, or `stream_between/3`, and leave that date field out of the
  query you pass in. Each window still stops at 10,000 hits.
  """

  @max_window 10_000
  @max_page 100

  @doc """
  Stream records from an offset search.

  `fetch` receives `[from: from, size: size]` and returns `{:ok, body}` or
  `{:error, reason}`.
  """
  def stream(fetch, opts \\ []) when is_function(fetch, 1) do
    resource(fetch, :offset, opts)
  end

  @doc """
  Collect an offset search. See `stream/2`.
  """
  def all(fetch, opts \\ []) when is_function(fetch, 1) do
    walk(fetch, init(opts, :offset), [])
  end

  @doc """
  Stream a full-text search.

  `fetch` receives `[page: page]`. Pages start at `:page` or 1, hold up to
  `:page_size` filings (default 100), and stop after page 100.
  """
  def by_page(fetch, opts \\ []) when is_function(fetch, 1) do
    resource(fetch, :page, opts)
  end

  @doc """
  Collect a full-text search. See `by_page/2`.
  """
  def all_by_page(fetch, opts \\ []) when is_function(fetch, 1) do
    walk(fetch, init(opts, :page), [])
  end

  @doc """
  Split an inclusive ISO date range into windows of `days` (default 31).

  `date_windows("2024-01-01", "2024-01-10", 7)` returns
  `[{"2024-01-01", "2024-01-07"}, {"2024-01-08", "2024-01-10"}]`.
  """
  def date_windows(start_date, end_date, days \\ 31) do
    with {:ok, start_date} <- Date.from_iso8601(to_string(start_date)),
         {:ok, end_date} <- Date.from_iso8601(to_string(end_date)) do
      cond do
        not is_integer(days) or days < 1 ->
          raise ArgumentError, "days must be at least 1"

        Date.compare(start_date, end_date) == :gt ->
          raise ArgumentError, "start is after end"

        true ->
          windows(start_date, end_date, days, [])
      end
    else
      _ -> raise ArgumentError, "dates must be YYYY-MM-DD"
    end
  end

  @doc """
  Collect every window of a date range.

  `search` is a function `(query, opts -> {:ok, body} | {:error, reason})`.
  Required options are `:from_date` and `:to_date`. `:date_field` defaults to
  `"filedAt"`. `:window_days` defaults to 31. The field clause is ANDed with
  `query` unless the query is empty or `"*"`.
  """
  def all_between(search, query, opts \\ []) when is_function(search, 2) and is_binary(query) do
    reduce_windows(search, query, opts, [], fn search, query, opts, acc ->
      case all(fn page -> search.(query, Keyword.merge(search_opts(opts), page)) end, opts) do
        {:ok, rows} -> {:cont, acc ++ rows}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Stream every window of a date range. A failed page raises `SecioEx.PageError`.

  The options match `all_between/3`.
  """
  def stream_between(search, query, opts \\ [])
      when is_function(search, 2) and is_binary(query) do
    field = date_field!(opts)
    days = Keyword.get(opts, :window_days, 31)
    from_date = required!(opts, :from_date)
    to_date = required!(opts, :to_date)

    from_date
    |> date_windows(to_date, days)
    |> Stream.flat_map(fn {from, to} ->
      window_query = and_range(query, field, from, to)

      stream(fn page -> search.(window_query, Keyword.merge(search_opts(opts), page)) end, opts)
    end)
  end

  defp resource(fetch, mode, opts) do
    Stream.resource(
      fn -> init(opts, mode) end,
      fn state -> next(fetch, state) end,
      fn _state -> :ok end
    )
  end

  defp next(_fetch, :done), do: {:halt, :done}

  defp next(fetch, state) do
    if halt_before?(state) do
      {:halt, :done}
    else
      case fetch.(args(state)) do
        {:ok, body} ->
          rows = records(body)
          taken = Enum.take(rows, state.left)

          if taken == [] do
            {:halt, :done}
          else
            {taken, advance(state, body, length(rows), length(taken))}
          end

        {:error, reason} ->
          raise SecioEx.PageError, error_opts(reason, state)

        other ->
          raise SecioEx.PageError, error_opts(other, state)
      end
    end
  end

  defp walk(_fetch, :done, acc), do: {:ok, concat(acc)}

  defp walk(fetch, state, acc) do
    if halt_before?(state) do
      {:ok, concat(acc)}
    else
      case fetch.(args(state)) do
        {:ok, body} ->
          rows = records(body)
          taken = Enum.take(rows, state.left)
          acc = if taken == [], do: acc, else: [taken | acc]
          next = advance(state, body, length(rows), length(taken))

          if taken == [] or next == :done do
            {:ok, concat(acc)}
          else
            walk(fetch, next, acc)
          end

        {:error, reason} ->
          fail(reason, state, acc)

        other ->
          fail(other, state, acc)
      end
    end
  end

  defp reduce_windows(search, query, opts, acc, fun) do
    field = date_field!(opts)
    days = Keyword.get(opts, :window_days, 31)
    from_date = required!(opts, :from_date)
    to_date = required!(opts, :to_date)

    result =
      Enum.reduce_while(date_windows(from_date, to_date, days), {:ok, acc}, fn {from, to},
                                                                               {:ok, acc} ->
        case fun.(search, and_range(query, field, from, to), opts, acc) do
          {:cont, acc} -> {:cont, {:ok, acc}}
          {:halt, error} -> {:halt, merge_error(acc, error)}
        end
      end)

    case result do
      {:ok, rows} -> {:ok, rows}
      {:error, _} = error -> error
    end
  end

  defp merge_error(acc, {:error, %{records: rows} = error}) do
    {:error, %{error | records: acc ++ rows}}
  end

  defp merge_error([], {:error, reason}), do: {:error, reason}

  defp merge_error(acc, {:error, reason}) do
    {:error, %{reason: reason, records: acc}}
  end

  defp advance(state, body, count, taken) do
    left = state.left - taken

    cond do
      left <= 0 -> :done
      is_list(body) -> :done
      short?(state, count) -> :done
      exact?(state, body) -> :done
      true -> move_or_stop(state, left)
    end
  end

  defp move_or_stop(state, left) do
    next = Map.put(move(state), :left, left)
    if halt_before?(next), do: :done, else: next
  end

  defp move(%{mode: :offset, from: from, size: size} = state), do: %{state | from: from + size}
  defp move(%{mode: :page, page: page} = state), do: %{state | page: page + 1}

  defp halt_before?(%{left: left}) when left <= 0, do: true
  defp halt_before?(%{mode: :offset, from: from}) when from >= @max_window, do: true
  defp halt_before?(%{mode: :page, page: page}) when page > @max_page, do: true
  defp halt_before?(_state), do: false

  defp short?(%{mode: :offset, size: size}, count), do: count < size
  defp short?(%{mode: :page, page_size: page_size}, count), do: count < page_size

  defp exact?(%{mode: :offset, from: from, size: size}, body) do
    case exact_total(body) do
      total when is_integer(total) -> from + size >= total
      _ -> false
    end
  end

  defp exact?(%{mode: :page, page: page, page_size: page_size}, body) do
    case exact_total(body) do
      total when is_integer(total) -> page * page_size >= total
      _ -> false
    end
  end

  defp args(%{mode: :offset, from: from, size: size}), do: [from: from, size: size]
  defp args(%{mode: :page, page: page}), do: [page: page]

  defp init(opts, mode) do
    %{
      mode: mode,
      from: if(mode == :offset, do: nonnegative!(Keyword.get(opts, :from, 0) || 0, "from")),
      page: if(mode == :page, do: positive!(Keyword.get(opts, :page, 1) || 1, "page")),
      size: if(mode == :offset, do: positive!(Keyword.get(opts, :size, 50) || 50, "size")),
      page_size:
        if(mode == :page, do: positive!(Keyword.get(opts, :page_size, 100) || 100, "page_size")),
      left: left!(opts)
    }
  end

  defp left!(opts) do
    limit = Keyword.get(opts, :limit, @max_window) || @max_window

    unless is_integer(limit) and limit >= 0 do
      raise ArgumentError, "limit must be a non-negative integer"
    end

    min(limit, @max_window)
  end

  defp records(%{"filings" => rows}) when is_list(rows), do: rows
  defp records(%{"data" => rows}) when is_list(rows), do: rows
  defp records(%{filings: rows}) when is_list(rows), do: rows
  defp records(%{data: rows}) when is_list(rows), do: rows
  defp records(rows) when is_list(rows), do: rows
  defp records(_body), do: []

  defp exact_total(%{"total" => total}), do: exact_total_value(total)
  defp exact_total(%{total: total}), do: exact_total_value(total)
  defp exact_total(_body), do: nil

  defp exact_total_value(%{"relation" => "eq", "value" => value}), do: parse_int(value)

  defp exact_total_value(%{relation: relation, value: value}) when relation in ["eq", :eq],
    do: parse_int(value)

  defp exact_total_value(%{"relation" => relation}) when is_binary(relation), do: nil

  defp exact_total_value(%{relation: relation}) when is_binary(relation) or is_atom(relation),
    do: nil

  defp exact_total_value(%{"value" => value}), do: parse_int(value)
  defp exact_total_value(%{value: value}), do: parse_int(value)
  defp exact_total_value(value), do: parse_int(value)

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp fail(reason, _state, []), do: {:error, reason}

  defp fail(reason, %{mode: :page, page: page}, acc) do
    {:error, %{reason: reason, page: page, records: concat(acc)}}
  end

  defp fail(reason, %{from: from}, acc) do
    {:error, %{reason: reason, from: from, records: concat(acc)}}
  end

  defp error_opts(reason, %{mode: :page, page: page}), do: [reason: reason, page: page]
  defp error_opts(reason, %{from: from}), do: [reason: reason, from: from]

  defp concat(acc) do
    acc |> Enum.reverse() |> Enum.concat()
  end

  defp windows(start_date, end_date, days, acc) do
    window_end = Date.add(start_date, days - 1)

    if Date.compare(window_end, end_date) != :lt do
      Enum.reverse([{Date.to_iso8601(start_date), Date.to_iso8601(end_date)} | acc])
    else
      next = Date.add(window_end, 1)
      pair = {Date.to_iso8601(start_date), Date.to_iso8601(window_end)}
      windows(next, end_date, days, [pair | acc])
    end
  end

  defp and_range(query, field, from, to) do
    clause = "#{field}:[#{from} TO #{to}]"
    if String.trim(query) in ["", "*"], do: clause, else: "(#{String.trim(query)}) AND #{clause}"
  end

  defp date_field!(opts) do
    field = Keyword.get(opts, :date_field, "filedAt")

    unless is_binary(field) and String.match?(field, ~r/^[A-Za-z][A-Za-z0-9_.]*$/) do
      raise ArgumentError, "invalid date field"
    end

    field
  end

  defp required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "pass :#{key}"
    end
  end

  defp search_opts(opts) do
    Keyword.drop(opts, [:from_date, :to_date, :date_field, :window_days])
  end

  defp positive!(value, _name) when is_integer(value) and value >= 1, do: value

  defp positive!(value, name) when is_integer(value) and value < 1 do
    raise ArgumentError, "#{name} must be at least 1"
  end

  defp positive!(_value, name), do: raise(ArgumentError, "#{name} must be an integer")

  defp nonnegative!(value, _name) when is_integer(value) and value >= 0, do: value

  defp nonnegative!(_value, name),
    do: raise(ArgumentError, "#{name} must be a non-negative integer")
end
