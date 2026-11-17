defmodule SecioEx.Client do
  @moduledoc """
  HTTP client shared by the sec-api.io endpoints.

  The key comes from `SecioEx.ApiKey`. It is sent in the `Authorization`
  header. Pass `auth: :query` or `use_auth_header: false` to send it as the
  `token` query parameter instead.

  Requests to `sec-api.io` time out after 60 seconds and ask for one gzip
  encoding. Stacked encodings are rejected. A gzip body is inflated only up
  to 512 MiB, and only up to 100 times the compressed size once it passes
  1 MiB. Redirects to another origin are not followed. Req retries only
  transient failures (408, 429, 500, 502, 503, 504, and transport errors).
  A 401 or 404 is returned immediately. Retry and redirect logs are disabled
  so a request URL cannot end up in the log.
  """

  @base "https://api.sec-api.io"
  @max_inflated_bytes 512 * 1024 * 1024
  @max_inflate_ratio 100
  @min_inflated_bytes 1_048_576

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

    headers = maybe_gzip(headers, url, opts)

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: Keyword.get(opts, :receive_timeout, 60_000),
        compressed: false,
        retry: :transient,
        max_retries: Keyword.get(opts, :max_retries, 2),
        retry_log_level: false,
        redirect_log_level: false,
        finch: [name: SecioEx.Finch]
      ]
      |> maybe_params(params)
      |> maybe_opt(:into, opts[:into])
      |> maybe_opt(:decode_body, opts[:decode_body])
      |> Keyword.merge(extra)

    req_opts = if opts[:plug], do: Keyword.put(req_opts, :plug, opts[:plug]), else: req_opts

    req_opts
    |> Req.new()
    |> Req.Request.prepend_response_steps(secio_ex_redirect: &guard_redirect/1)
    |> Req.request()
    |> normalize(key, opts)
  end

  defp maybe_gzip(headers, url, opts) do
    if Keyword.get(opts, :compressed, true) and opts[:into] == nil and trusted_api_host?(url) do
      [{"accept-encoding", "gzip"} | headers]
    else
      headers
    end
  end

  defp trusted_api_host?(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
    host == "sec-api.io" or String.ends_with?(host, ".sec-api.io")
  end

  defp guard_redirect({request, %Req.Response{status: status} = response})
       when status in [301, 302, 303, 307, 308] do
    case Req.Response.get_header(response, "location") do
      [location | _] ->
        target = URI.merge(request.url, location)

        if same_origin?(request.url, target) do
          {request, response}
        else
          Req.Request.halt(request, response)
        end

      _ ->
        {request, response}
    end
  end

  defp guard_redirect(other), do: other

  defp same_origin?(%URI{} = left, %URI{} = right) do
    origin(left) == origin(right)
  end

  defp origin(%URI{} = uri) do
    scheme = uri.scheme |> to_string() |> String.downcase()
    host = uri.host |> to_string() |> String.downcase()
    {scheme, host, origin_port(scheme, uri.port)}
  end

  defp origin_port("http", nil), do: 80
  defp origin_port("https", nil), do: 443
  defp origin_port(_scheme, port), do: port

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

  defp normalize({:ok, %Req.Response{status: status} = response}, _key, opts)
       when status in 200..299 do
    inflate_response(response, opts)
  end

  defp normalize({:ok, %Req.Response{status: status, body: body}}, key, _opts) do
    {:error, %{status_code: status, body: redact(body, key)}}
  end

  defp normalize({:error, error}, key, _opts) do
    {:error, redact_error(error, key)}
  end

  defp inflate_response(%Req.Response{body: body}, _opts) when not is_binary(body) do
    {:ok, body}
  end

  defp inflate_response(%Req.Response{body: body} = response, opts) do
    case encodings(response) do
      [] ->
        {:ok, body}

      ["gzip"] ->
        with {:ok, inflated} <- inflate_gzip(body, inflate_limit(body, opts)) do
          {:ok, maybe_decode_json(inflated, response)}
        end

      _other ->
        {:error, %{reason: :unsupported_encoding}}
    end
  end

  defp encodings(response) do
    response
    |> Req.Response.get_header("content-encoding")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 in ["", "identity"]))
  end

  defp inflate_limit(body, opts) do
    absolute = Keyword.get(opts, :max_inflated_bytes, @max_inflated_bytes)
    ratio = Keyword.get(opts, :max_inflate_ratio, @max_inflate_ratio)
    floor = Keyword.get(opts, :min_inflated_bytes, @min_inflated_bytes)
    min(absolute, max(floor, byte_size(body) * ratio))
  end

  defp inflate_gzip(body, limit) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z, 31)
      collect_inflate(z, body, limit, 0, [])
    catch
      :error, _ -> {:error, %{reason: :invalid_encoding}}
    after
      :zlib.close(z)
    end
  end

  defp collect_inflate(z, data, limit, size, acc) do
    case :zlib.safeInflate(z, data) do
      {:continue, output} ->
        size = size + IO.iodata_length(output)

        if size > limit do
          {:error, %{reason: :inflated_too_large}}
        else
          collect_inflate(z, [], limit, size, [output | acc])
        end

      {:finished, output} ->
        size = size + IO.iodata_length(output)

        if size > limit do
          {:error, %{reason: :inflated_too_large}}
        else
          {:ok, IO.iodata_to_binary(Enum.reverse([output | acc]))}
        end

      {:error, _} ->
        {:error, %{reason: :invalid_encoding}}
    end
  end

  defp maybe_decode_json(body, response) do
    type =
      response
      |> Req.Response.get_header("content-type")
      |> List.first("")
      |> String.downcase()

    if String.contains?(type, "json") do
      case Jason.decode(body) do
        {:ok, decoded} -> decoded
        {:error, _} -> body
      end
    else
      body
    end
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
