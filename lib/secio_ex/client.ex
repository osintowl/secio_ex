defmodule SecioEx.Client do
  @moduledoc """
  HTTP client shared by the sec-api.io endpoints.

  The key comes from `SecioEx.ApiKey`. It is sent in the `Authorization`
  header. Pass `auth: :query` or `use_auth_header: false` to send it as the
  `token` query parameter instead.

  Requests time out after 60 seconds and ask for a gzip body. Req retries
  only transient failures (408, 429, 500, 502, 503, 504, and transport
  errors). A 401 or 404 is returned immediately. Retry logs are disabled
  so a request URL cannot end up in the log.
  """

  @base "https://api.sec-api.io"

  @doc """
  POST a Lucene search.

  `opts` accepts `:from`, `:size`, `:sort`, plus the options of `post/3`.
  Sort is omitted when it is nil. `from` defaults to 0 and `size` to 50.
  """
  def search(path, query, opts \\ []) when is_binary(query) do
    body =
      %{
        "query" => query,
        "from" => Keyword.get(opts, :from, 0),
        "size" => Keyword.get(opts, :size, 50)
      }
      |> maybe_put("sort", opts[:sort])

    post(path, body, opts)
  end

  @doc """
  POST a search, filling in any of `defaults` the caller did not pass.
  """
  def dataset(path, query, opts \\ [], defaults \\ []) when is_binary(query) do
    opts =
      Enum.reduce(defaults, opts, fn {key, value}, acc -> Keyword.put_new(acc, key, value) end)

    search(path, query, opts)
  end

  @doc "Default filing sort: most recently filed first."
  def filed_at_desc, do: [%{"filedAt" => %{"order" => "desc"}}]

  @doc "Enforcement, litigation, and administrative-proceeding sort."
  def released_at_desc, do: [%{"releasedAt" => %{"order" => "desc"}}]

  @doc "EDGAR entity sort. This dataset has no `filedAt` field."
  def cik_updated_desc, do: [%{"cikUpdatedAt" => %{"order" => "desc"}}]

  @doc "Quote a Lucene field value."
  def phrase(field, value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    ~s(#{field}:"#{escaped}")
  end

  @doc "Encode one path segment."
  def encode_segment(value) do
    value |> to_string() |> String.trim() |> URI.encode(&URI.char_unreserved?/1)
  end

  @doc """
  POST JSON to a path under `https://api.sec-api.io`.

  `""` and `"/"` post to the host with no extra path. That is the filing query API.
  """
  def post(path, body, opts \\ []) when is_map(body) do
    request(:post, expand(path), opts, json: body)
  end

  @doc """
  GET a path under `https://api.sec-api.io`.

  Pass query parameters with `:params`, as a keyword list or a map.
  An absolute `http` or `https` URL is used as given.
  """
  def get(path, opts \\ []) when is_binary(path) do
    request(:get, expand(path), opts, [])
  end

  @doc "GET an absolute URL. Used for the archive and the PDF renderer."
  def get_absolute(url, opts \\ []) when is_binary(url) do
    request(:get, url, opts, [])
  end

  defp expand(path) when path in ["", "/"], do: @base

  defp expand("http://" <> _ = url), do: url
  defp expand("https://" <> _ = url), do: url

  defp expand(path) do
    @base <> "/" <> String.trim_leading(path, "/")
  end

  defp request(method, url, opts, extra) do
    key = SecioEx.ApiKey.resolve!(opts)
    params = normalize_params(opts[:params])

    {headers, params} =
      case auth_mode(opts) do
        :header ->
          {[{"Authorization", key}], params}

        :query ->
          {[], Keyword.put(params, :token, key)}
      end

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: Keyword.get(opts, :receive_timeout, 60_000),
        compressed: Keyword.get(opts, :compressed, true),
        retry: :transient,
        max_retries: Keyword.get(opts, :max_retries, 2),
        retry_log_level: false,
        finch: [name: SecioEx.Finch]
      ]
      |> maybe_params(params)
      |> maybe_opt(:into, opts[:into])
      |> maybe_opt(:decode_body, opts[:decode_body])
      |> Keyword.merge(extra)

    req_opts = if opts[:plug], do: Keyword.put(req_opts, :plug, opts[:plug]), else: req_opts

    req_opts
    |> Req.request()
    |> normalize(key)
  end

  defp auth_mode(opts) do
    cond do
      opts[:auth] in [:header, :query] -> opts[:auth]
      opts[:use_auth_header] == false -> :query
      opts[:auth] in [nil, false] -> :header
      true -> raise ArgumentError, "auth must be :header or :query"
    end
  end

  defp normalize_params(nil), do: []
  defp normalize_params(params) when is_list(params), do: params
  defp normalize_params(params) when is_map(params), do: Map.to_list(params)

  defp maybe_params(opts, []), do: opts
  defp maybe_params(opts, params), do: Keyword.put(opts, :params, params)

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize({:ok, %Req.Response{status: status, body: body}}, _key)
       when status in 200..299 do
    {:ok, body}
  end

  defp normalize({:ok, %Req.Response{status: status, body: body}}, key) do
    {:error, %{status_code: status, body: redact(body, key)}}
  end

  defp normalize({:error, error}, key) do
    {:error, redact_error(error, key)}
  end

  defp redact_error(error, key) do
    rendered = inspect(error, limit: 30, printable_limit: 400)

    if String.contains?(rendered, key) or String.contains?(rendered, "token=") or
         String.contains?(rendered, "apiKey=") do
      rendered
      |> String.replace(key, "[redacted]")
      |> String.replace(~r/apiKey=[^&\s"'\\]+/, "apiKey=[redacted]")
      |> String.replace(~r/token=[^&\s"'\\]+/, "token=[redacted]")
    else
      error
    end
  end

  defp redact(value, key) when is_binary(value) do
    if String.contains?(value, key), do: String.replace(value, key, "[redacted]"), else: value
  end

  defp redact(value, key) when is_map(value) do
    Map.new(value, fn {item_key, item_value} ->
      {redact(item_key, key), redact(item_value, key)}
    end)
  end

  defp redact(value, key) when is_list(value), do: Enum.map(value, &redact(&1, key))
  defp redact(value, _key), do: value
end
